class OperationsReportTickJob
  include Sidekiq::Worker
  sidekiq_options queue: 'operations_reports', retry: 3

  def perform
    return unless ENV['AI_ENGLISH_REPORTS_ENABLED'] == 'true'
    record_health('running', started_at: Time.current.iso8601)
    Apartment::Tenant.switch('public') do
      since = Time.iso8601(ENV.fetch('AI_ENGLISH_REPORTS_ENABLED_AT'))
      OperationsReportWindow.due_ends(since: since).each do |ending|
        next if OperationsReportDelivery.where(period_end: ending, state: %w[sent delivering unknown]).exists?
        OperationsReportJob.perform_async(ending.iso8601)
      end
    end
    record_health('completed', completed_at: Time.current.iso8601)
  rescue StandardError => e
    record_health('failed', failed_at: Time.current.iso8601, error_class: e.class.name)
    raise
  end

  private

  def record_health(state, **fields)
    Sidekiq.redis do |redis|
      redis.hset('aienglish:operations_reports:health', { 'state' => state }.merge(fields.transform_keys(&:to_s)))
      redis.expire('aienglish:operations_reports:health', 24.hours.to_i)
    end
  rescue StandardError => e
    Rails.logger.warn("[OperationsReportTick] Health unavailable error=#{e.class}")
  end
end
