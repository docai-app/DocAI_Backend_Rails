class EssayGenerationRecoveryJob
  include Sidekiq::Worker
  sidekiq_options queue: 'generation_recovery', retry: false

  def perform
    return unless ENV['AI_ENGLISH_RECOVERY_ENABLED'] == 'true'
    since = Time.iso8601(ENV.fetch('AI_ENGLISH_RECOVERY_ENABLED_AT'))
    Apartment::Tenant.switch('public') do
      snapshot = EssayGenerationQueueSnapshot.new
      reconciler = EssayGenerationReconciler.new(snapshot: snapshot)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
      # Never automatically adopt historical pending without provider tracking.
      runs = EssayGenerationRun.joins(essay_grading: :essay_assignment)
        .where(state: EssayGenerationRun::ACTIVE_STATES).where('essay_generation_runs.created_at >= ?', since)
        .merge(EssayAssignment.where(category: %w[essay speaking_essay speaking_conversation sentence_builder talk_lab_speaking]))
        .where("CASE WHEN essay_generation_runs.state IN ('queued', 'retry_wait') THEN COALESCE(next_retry_at, queued_at) ELSE COALESCE(started_at, queued_at) END < ?", 2.hours.ago)
        .order(Arel.sql('recovery_checked_at ASC NULLS FIRST')).limit(100)
      runs.each do |run|
        # A slow provider must not pile up a new scanner every five minutes.
        # Each provider GET has its own bounded connect/read timeouts.
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        reconciler.call(run)
      rescue StandardError => e
        Rails.logger.error("[EssayGenerationRecovery] run=#{run.id} check=#{e.class}")
      end
    end
  end
end
