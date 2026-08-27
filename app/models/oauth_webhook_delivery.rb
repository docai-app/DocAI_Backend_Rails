# frozen_string_literal: true

class OauthWebhookDelivery < ApplicationRecord
  self.table_name = 'oauth_webhook_deliveries'

  STATUSES = %w[pending delivered failed dead_letter].freeze

  belongs_to :oauth_application, class_name: 'OauthApplication'

  validates :event_type, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending_retry, lambda {
    where(status: %w[pending failed])
      .where('next_retry_at IS NULL OR next_retry_at <= ?', Time.current)
  }

  def as_admin_json
    {
      id: id,
      oauth_application_id: oauth_application_id,
      event_type: event_type,
      status: status,
      attempt_count: attempt_count,
      last_http_status: last_http_status,
      last_error: last_error,
      next_retry_at: next_retry_at,
      delivered_at: delivered_at,
      created_at: created_at,
      payload_summary: {
        type: payload.is_a?(Hash) ? payload['type'] : nil,
        client_id: payload.is_a?(Hash) ? payload['client_id'] : nil,
        created_at: payload.is_a?(Hash) ? payload['created_at'] : nil
      }
    }
  end

  def mark_delivered!(http_status:)
    update!(
      status: 'delivered',
      last_http_status: http_status,
      last_error: nil,
      next_retry_at: nil,
      delivered_at: Time.current
    )
  end

  def mark_attempt_failed!(http_status:, error:, max_retries:)
    next_count = attempt_count + 1
    dead = next_count >= max_retries
    update!(
      status: dead ? 'dead_letter' : 'failed',
      attempt_count: next_count,
      last_http_status: http_status,
      last_error: error.to_s.truncate(2000),
      next_retry_at: dead ? nil : Time.current + retry_delay_for(next_count)
    )
  end

  private

  def retry_delay_for(attempt)
    case attempt
    when 1 then 1.minute
    when 2 then 5.minutes
    when 3 then 15.minutes
    when 4 then 1.hour
    else 6.hours
    end
  end
end
