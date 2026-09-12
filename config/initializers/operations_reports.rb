# Uses existing Sidekiq scheduler; not the local Codex app or an extra mail system.
# A five-minute reconciliation also catches boundaries missed during worker downtime.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    if ENV['AI_ENGLISH_REPORT_WORKER'] == 'true' && ENV['AI_ENGLISH_REPORTS_ENABLED'] == 'true'
      Time.iso8601(ENV.fetch('AI_ENGLISH_REPORTS_ENABLED_AT'))
      Sidekiq.set_schedule('ai_english_operations_report', {
        'cron' => '*/5 * * * * Asia/Macau',
        'class' => 'OperationsReportTickJob', 'queue' => 'operations_reports'
      })
      Sidekiq.reload_schedule!
      Sidekiq::Scheduler.instance.reload_schedule!
      OperationsReportTickJob.perform_async
    elsif ENV['AI_ENGLISH_REPORT_WORKER'] == 'true'
      Sidekiq.remove_schedule('ai_english_operations_report')
    end
  end
end
