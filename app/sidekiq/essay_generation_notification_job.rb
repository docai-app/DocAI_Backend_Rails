# frozen_string_literal: true

class EssayGenerationNotificationJob
  include Sidekiq::Worker
  sidekiq_options retry: 3

  def perform(run_id, token)
    run = EssayGenerationRun.find_by(id: run_id)
    return unless run

    attention = run.state == 'unknown' && run.attention_required_at.present?
    return unless run.token == token && (run.state == 'failed' || attention)
    field = attention ? :attention_notified_at : :notified_at
    return if run[field].present?
    delivery = EssayGenerationNotification.create_or_find_by!(essay_generation_run: run, token: token, kind: attention ? 'attention' : 'failure')
    return if %w[sent delivering unknown].include?(delivery.state)
    begin
      mail = AdminNotificationMailer.assignment_stopped_notification(run.essay_grading, generation: run)
      mail.message.encoded # Render failures can be safely retried before transport.
    rescue StandardError => e
      EssayGenerationNotification.where(id: delivery.id, claimed_at: nil).update_all(state: 'build_failed', failure_class: e.class.name)
      raise
    end
    claimed = false
    run.with_lock do
      if run.token == token && run.state == (attention ? 'unknown' : 'failed') && run[field].nil?
        delivery.update!(state: 'delivering', claimed_at: Time.current, failure_class: nil)
        run.update!(field => Time.current)
        claimed = true
      end
    end
    return unless claimed
    begin
      mail.deliver_now
      delivery.update!(state: 'sent', sent_at: Time.current)
    rescue StandardError => e
      delivery.update_columns(state: 'unknown', failure_class: e.class.name)
      Rails.logger.error("[EssayGenerationNotification] delivery=#{delivery.id} transport=#{e.class}")
    end
  end
end
