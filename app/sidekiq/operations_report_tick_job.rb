class OperationsReportTickJob
  include Sidekiq::Worker
  sidekiq_options queue: 'operations_reports', retry: 3

  def perform
    return unless ENV['AI_ENGLISH_REPORTS_ENABLED'] == 'true'
    Apartment::Tenant.switch('public') do
      since = Time.iso8601(ENV.fetch('AI_ENGLISH_REPORTS_ENABLED_AT'))
      OperationsReportWindow.due_ends(since: since).each do |ending|
        next if OperationsReportDelivery.where(period_end: ending, state: %w[sent delivering unknown]).exists?
        OperationsReportJob.perform_async(ending.iso8601)
      end
    end
  end
end
