class EssayGenerationReconciler
  OBSERVATION_GAP = 1.minute

  def initialize(snapshot:, provider_lookup: DifyWorkflowRecovery)
    @snapshot, @provider_lookup = snapshot, provider_lookup
  end

  def call(run)
    token = run.token
    context = nil
    eligible = false
    run.essay_grading.with_lock do
      run.reload
      next unless run.token == token && run.recovery_due?
      run.update!(recovery_checked_at: Time.current)
      observation = @snapshot.status(run)
      if observation != :absent
        run.update!(missing_since: nil)
        next
      end
      unless run.missing_since && run.missing_since <= OBSERVATION_GAP.ago
        run.update!(missing_since: Time.current)
        next
      end
      # A queued worker must first claim under this same lock. Obsolete queue
      # deliveries cannot claim the new token, even if Redis iteration missed one.
      if %w[queued retry_wait].include?(run.state)
        run.recover_dispatch!
        next
      end
      context = run.provider_context.deep_dup
      if run.recovery_version == 1 && (context.empty? || context['resolved'] && !context['terminal'])
        run.recover_dispatch!
        next
      end
      if run.recovery_version != 1 || context['provider'] != 'workflow'
        run.require_recovery_attention!('provider_result_unconfirmed')
        next
      end
      eligible = true
    end
    return unless eligible

    # External GET outside transactions; every write afterwards rechecks the fence.
    terminal = context['terminal']
    provider_state = nil
    unless terminal
      key = provider_key(run, context['stage'])
      if key.present? && context['run_id'].present? && Digest::SHA256.hexdigest(key) == context['key_digest']
        data = @provider_lookup.lookup(context['run_id'], app_key: key, run_url: EssayGradingService::API_URL)
        provider_state = data && data['status']
        terminal = { 'event' => 'workflow_finished', 'data' => data } if %w[succeeded failed stopped].include?(provider_state)
      end
    end
    run.essay_grading.with_lock do
      run.reload
      next unless run.token == token && run.recovery_due? && run.provider_context == context
      next unless %w[running checking unknown].include?(run.state)
      if terminal
        # Reuse the original output; the normal worker validates/persists it.
        # This continues the original attempt, not another provider POST.
        run.recover_dispatch!(terminal: terminal)
      elsif %w[running pending paused].include?(provider_state)
        run.update!(missing_since: nil)
      else
        run.require_recovery_attention!('provider_result_unconfirmed')
      end
    end
  end

  private

  def provider_key(run, stage)
    grading = run.essay_grading
    case stage
    when 'grading' then grading.grading['app_key'] if run.kind == 'grading'
    when 'general_context' then grading.general_context['app_key'] if run.kind == 'grading'
    when 'supplement' then ENV['essay_grading_supplement_practice_app_key'] if run.kind == 'supplement'
    end
  end
end
