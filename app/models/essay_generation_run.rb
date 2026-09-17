# frozen_string_literal: true

# One authoritative slot per grading and workflow. A token fences obsolete jobs.
class EssayGenerationRun < ApplicationRecord
  include EssayGenerationRecoveryState
  class Unavailable < StandardError; end
  class StaleExecution < StandardError; end
  class OutcomeUnknown < StandardError; end
  MAX_ATTEMPTS = 3
  QUEUE_TIMEOUT = 2.hours
  RETRY_DELAYS = [30.seconds, 2.minutes].freeze
  ACTIVE_STATES = %w[queued running checking retry_wait unknown].freeze

  belongs_to :essay_grading
  validates :kind, inclusion: { in: %w[grading supplement] }
  validates :state, inclusion: { in: %w[queued running checking retry_wait ready failed unknown cancelled] }
  after_commit :dispatch, if: :dispatch_needed?

  # Only authenticated Admin controllers/services may call this entry point.
  # This is an explicit new attempt, not automatic recovery of an unknown result.
  def self.request_admin_rerun!(grading)
    request!(grading, kind: 'grading', force: true, require_new: true, admin_override: true)
  end

  def self.request!(grading, kind:, manual: false, force: false, require_new: false, admin_override: false)
    raise ArgumentError, 'Admin override is only for main grading' if admin_override && kind != 'grading'

    result = nil
    grading.with_lock do
      run = find_by(essay_grading_id: grading.id, kind: kind)
      if admin_override
        supersede_supplement_for_admin!(grading)
        meta = grading.meta || {}
        history = Array(meta['admin_reruns']).last(19)
        history << { 'at' => Time.current.iso8601, 'previous_state' => run&.state,
          'previous_attempts' => run&.attempts, 'previous_run_id' => run&.provider_context&.dig('run_id') }
        grading.update_columns(meta: meta.merge('admin_reruns' => history))
      elsif kind == 'grading' && where(essay_grading_id: grading.id, kind: 'supplement', state: ACTIVE_STATES).exists?
        raise Unavailable, 'Please wait for the current exercise task before rerunning grading.'
      end
      # A duplicate legacy queue delivery is not a new retry budget.
      if run && !manual && !force
        result = run
        next
      end
      if !admin_override && run && ACTIVE_STATES.include?(run.state) && !run.stale_queue?
        if require_new
          message = run.state == 'unknown' ? 'The previous task result must be confirmed before retrying.' : 'A task is already queued or processing. No new retry was started.'
          raise Unavailable, message
        end
        result = run
        next
      end
      if kind == 'supplement' && grading.supplement_practice_records.exists?
        raise Unavailable, 'An existing answer record must be preserved.'
      end
      raise Unavailable, 'The main grading must be ready first.' if kind == 'supplement' && !grading.graded?
      # A main-workflow rerun must not replace an already valid exercise.
      if kind == 'supplement' && !force && SupplementPracticeAvailability.call(grading)[:state] == 'ready'
        result = run
        next
      end
      if run&.state == 'ready' && !force
        result = run
        next
      end
      if manual && run && run.finished_at && run.finished_at > 1.minute.ago
        raise Unavailable, 'Please contact your teacher or try again later.'
      end
      run ||= new(essay_grading: grading, kind: kind)
      run.assign_attributes(
        token: SecureRandom.uuid, state: 'queued', attempts: 0,
        manual_retries: run.manual_retries.to_i + ((manual || admin_override) ? 1 : 0),
        completed_stages: [], failure_code: nil, queued_at: Time.current,
        started_at: nil, finished_at: nil, next_retry_at: nil, notified_at: nil,
        provider_context: {}, recovery_count: 0, recovery_version: 0, resume_pending: false,
        missing_since: nil, recovery_checked_at: nil, attention_required_at: nil, attention_notified_at: nil
      )
      run.save!
      grading.update_columns(status: EssayGrading.statuses[:pending]) if kind == 'grading'
      result = run
    end
    result
  end

  def self.supersede_supplement_for_admin!(grading)
    supplement = find_by(essay_grading_id: grading.id, kind: 'supplement', state: ACTIVE_STATES)
    return unless supplement

    # Keep usable questions (and all student answer records). Only an unfinished
    # exercise without valid content needs a new generation after grading finishes.
    ready = begin
      SupplementPracticeValidator.parse(grading).present?
    rescue JSON::ParserError, ArgumentError, OldDataFormatError
      false
    end
    supplement.update!(token: SecureRandom.uuid, state: ready ? 'ready' : 'cancelled',
      finished_at: Time.current, next_retry_at: nil, attention_required_at: nil,
      failure_code: ready ? nil : 'admin_grading_rerun')
  end
  private_class_method :supersede_supplement_for_admin!

  def checking!(expected_token)
    essay_grading.with_lock do
      reload
      raise StaleExecution unless token == expected_token && %w[running checking].include?(state)
      update!(state: 'checking')
    end
  end

  def stale_queue?
    %w[queued retry_wait].include?(state) && (next_retry_at || queued_at)&.<(QUEUE_TIMEOUT.ago)
  end

  def claim!(expected_token)
    # Match request!/persist_stage! lock order. Otherwise a stale-queue retry
    # could replace a token just as a worker claims it and starts a provider call.
    essay_grading.with_lock do
      reload
      return false unless token == expected_token && %w[queued retry_wait].include?(state)
      return false if next_retry_at && next_retry_at > Time.current
      return false if attempts >= MAX_ATTEMPTS && !resume_pending

      update!(state: 'running', attempts: attempts + (resume_pending ? 0 : 1), started_at: Time.current,
        recovery_version: 1, resume_pending: false, missing_since: nil, attention_required_at: nil)
    end
    true
  end

  # Do not hold a transaction during provider calls. Save only under the current token.
  def persist_stage!(expected_token, stage)
    essay_grading.with_lock do
      reload
      raise StaleExecution unless token == expected_token && %w[running checking].include?(state)
      raise Unavailable, 'An existing answer record must be preserved.' if kind == 'supplement' && essay_grading.supplement_practice_records.exists?

      yield essay_grading
      update!(state: 'running', completed_stages: (completed_stages + [stage]).uniq,
        provider_context: provider_context['stage'] == stage ? {} : provider_context)
    end
    true
  end

  def finish!(expected_token, success:, unknown: false)
    essay_grading.with_lock do
      reload
      return unless token == expected_token && %w[running checking].include?(state)

      if success
        update!(state: 'ready', finished_at: Time.current, failure_code: nil)
        essay_grading.update_columns(status: EssayGrading.statuses[:graded]) if kind == 'grading'
        if kind == 'grading' && essay_grading.category == 'essay' && !essay_grading.supplement_practice_records.exists?
          supplement = self.class.find_by(essay_grading_id: essay_grading.id, kind: 'supplement')
          restart = supplement&.state == 'cancelled' && supplement.failure_code == 'admin_grading_rerun'
          self.class.request!(essay_grading, kind: 'supplement', force: restart)
        end
      elsif unknown
        # A timeout is not permission to issue another billable provider call.
        update!(state: 'unknown', failure_code: 'outcome_unknown')
      elsif attempts < MAX_ATTEMPTS
        update!(state: 'retry_wait', token: SecureRandom.uuid, next_retry_at: Time.current + RETRY_DELAYS.fetch(attempts - 1), failure_code: 'generation_failed', provider_context: {}, missing_since: nil)
      else
        update!(state: 'failed', finished_at: Time.current, failure_code: 'generation_failed')
        essay_grading.update_columns(status: EssayGrading.statuses[:stopped]) if kind == 'grading'
      end
    end
  end

  def public_state
    retryable = state == 'failed' || stale_queue?
    retryable &&= !finished_at || finished_at <= 1.minute.ago
    retryable &&= !essay_grading.supplement_practice_records.exists? if kind == 'supplement'
    retryable &&= essay_grading.graded? if kind == 'supplement'
    { state: state, can_retry: !!retryable, attempts: attempts, queued_at: queued_at, started_at: started_at, retry_after: next_retry_at,
      requires_attention: attention_required_at.present?, recovery_count: recovery_count }
  end

  private

  def dispatch_needed?
    previous_changes.key?('token') || (previous_changes.key?('state') && state == 'failed') || previous_changes.key?('attention_required_at')
  end

  def dispatch
    if %w[queued retry_wait].include?(state)
      EssayGenerationJob.perform_at(next_retry_at || Time.current, id, token)
    elsif state == 'failed'
      EssayGenerationNotificationJob.perform_async(id, token)
    elsif state == 'unknown' && attention_required_at.present? && attention_notified_at.nil?
      EssayGenerationNotificationJob.perform_async(id, token)
    end
  rescue StandardError => e
    # Do not pretend enqueue succeeded. The queued slot remains safely recoverable.
    Rails.logger.error("[EssayGenerationRun] Dispatch unavailable run=#{id} error=#{e.class}")
  end
end
