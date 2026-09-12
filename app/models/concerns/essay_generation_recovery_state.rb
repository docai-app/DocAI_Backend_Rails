require 'digest'

# Durable provider boundary: an absent worker is not proof that a paid call failed.
module EssayGenerationRecoveryState
  extend ActiveSupport::Concern

  def begin_provider!(expected_token, stage, provider: 'opaque', app_key: nil)
    result = nil
    essay_grading.with_lock do
      reload
      ensure_execution!(expected_token)
      context = provider_context
      if context['stage'] == stage && context['terminal'].present?
        result = [context['terminal']]
      else
        raise EssayGenerationRun::OutcomeUnknown if context.present? && !context['resolved']
        update!(provider_context: { 'stage' => stage, 'provider' => provider,
          'key_digest' => app_key.present? ? Digest::SHA256.hexdigest(app_key) : nil,
          'resolved' => false }.compact)
      end
    end
    result
  end

  def observe_provider!(expected_token, event)
    return unless event.is_a?(Hash)
    id = event['workflow_run_id'] || (event['event'] == 'workflow_started' && event.dig('data', 'id'))
    terminal = event['event'] == 'workflow_finished' && %w[succeeded failed stopped].include?(event.dig('data', 'status'))
    return unless id.present? || terminal
    essay_grading.with_lock do
      reload
      ensure_execution!(expected_token)
      context = provider_context.deep_dup
      next unless context['provider'] == 'workflow'
      if id.present?
        raise EssayGenerationRun::OutcomeUnknown unless id.is_a?(String) && id.match?(/\A[0-9a-f-]{36}\z/i)
        raise EssayGenerationRun::OutcomeUnknown if context['run_id'].present? && context['run_id'] != id
        context['run_id'] = id
      end
      context.merge!('terminal' => event, 'resolved' => true) if terminal
      update!(provider_context: context) if context != provider_context
    end
  end

  def resolve_provider!(expected_token)
    essay_grading.with_lock do
      reload
      ensure_execution!(expected_token)
      update!(provider_context: provider_context.merge('resolved' => true)) if provider_context.present?
    end
  end

  def ensure_execution!(expected_token)
    raise EssayGenerationRun::StaleExecution unless token == expected_token && %w[running checking].include?(state)
  end

  def with_execution!(expected_token)
    essay_grading.with_lock do
      reload.ensure_execution!(expected_token)
      yield essay_grading
    end
  end

  def recovery_due?(now = Time.current)
    return false unless EssayGenerationRun::ACTIVE_STATES.include?(state)
    since = %w[queued retry_wait].include?(state) ? (next_retry_at || queued_at) : (started_at || queued_at)
    since && since < now - EssayGenerationRun::QUEUE_TIMEOUT
  end

  # Must be called under the grading lock after rechecking token and provider context.
  def recover_dispatch!(terminal: nil)
    # A resumed result may itself lose its queue delivery; never discard it.
    terminal ||= provider_context['terminal'] if resume_pending
    resume = terminal.present? || checkpoints_complete?
    if recovery_count >= 2 || (attempts >= EssayGenerationRun::MAX_ATTEMPTS && !resume)
      if resume
        require_recovery_attention!('recovery_budget_exhausted')
        return
      end
      update!(state: 'failed', finished_at: Time.current, failure_code: 'recovery_exhausted', missing_since: nil)
      essay_grading.update_columns(status: EssayGrading.statuses[:stopped]) if kind == 'grading'
      return
    end
    context = terminal ? provider_context.merge('terminal' => terminal, 'resolved' => true) : {}
    update!(state: 'queued', token: SecureRandom.uuid, queued_at: Time.current, next_retry_at: nil,
      missing_since: nil, recovery_count: recovery_count + 1, resume_pending: resume,
      provider_context: context, attention_required_at: nil, failure_code: nil)
  end

  def checkpoints_complete?
    required = if kind == 'supplement'
      ['supplement']
    else
      stages = ['grading']
      stages << 'general_context' if essay_grading.general_context['app_key'].present?
      stages << 'revised_essay' if essay_grading.revised_essay_app_key.present?
      stages.concat(%w[audio speaking_scoring]) if essay_grading.category == 'speaking_essay'
      stages
    end
    (required - completed_stages).empty?
  end

  def require_recovery_attention!(code)
    # Unknown disallows further execution writes even without rotating the token;
    # keep the token so subsequent read-only provider checks can recover its result.
    update!(state: 'unknown', failure_code: code,
      attention_required_at: attention_required_at || Time.current)
  end
end
