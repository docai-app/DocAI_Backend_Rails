class OperationsReportJob
  include Sidekiq::Worker
  sidekiq_options queue: 'operations_reports', retry: 3

  def perform(ending_iso)
    return unless ENV['AI_ENGLISH_REPORTS_ENABLED'] == 'true'
    Apartment::Tenant.switch('public') { deliver_report(Time.iso8601(ending_iso)) }
  end

  private

  def deliver_report(ending)
    beginning = OperationsReportWindow.start_for(ending)
    row = OperationsReportDelivery.create_or_find_by!(period_end: ending) { |r| r.period_start = beginning }
    return if %w[sent delivering unknown].include?(row.state)
    begin
      summary = OperationsStatusReport.new(beginning: beginning, ending: ending).call
      # Render/validate recipient before claiming transport. Failures here are safe to retry.
      message = AdminNotificationMailer.operations_status_report(summary).message
      message.encoded
    rescue StandardError => e
      OperationsReportDelivery.where(id: row.id, claimed_at: nil).update_all(state: 'build_failed', failure_class: e.class.name)
      raise
    end
    claimed = false
    row.with_lock do
      unless %w[sent delivering unknown].include?(row.state)
        row.update!(state: 'delivering', claimed_at: Time.current, summary: summary, failure_class: nil)
        claimed = true
      end
    end
    return unless claimed
    begin
      message.deliver!
      row.update!(state: 'sent', sent_at: Time.current)
    rescue StandardError => e
      # SMTP acceptance may be ambiguous: never send the same period twice automatically.
      row.update_columns(state: 'unknown', failure_class: e.class.name)
      Rails.logger.error("[OperationsReportJob] delivery=#{row.id} transport=#{e.class}")
    end
  end
end
