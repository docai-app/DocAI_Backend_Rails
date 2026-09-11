# frozen_string_literal: true

class EssayGenerationNotificationJob
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(run_id, token)
    run = EssayGenerationRun.find_by(id: run_id)
    return unless run

    run.with_lock do
      return unless run.token == token && run.state == 'failed' && run.notified_at.nil?

      # At-most-once dispatch: an ambiguous mail transport failure must not spam.
      run.update!(notified_at: Time.current)
    end
    AdminNotificationMailer.assignment_stopped_notification(run.essay_grading, generation: run).deliver_now
  end
end
