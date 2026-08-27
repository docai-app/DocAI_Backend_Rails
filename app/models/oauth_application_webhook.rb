# frozen_string_literal: true

class OauthApplicationWebhook < ApplicationRecord
  self.table_name = 'oauth_application_webhooks'

  DEFAULT_EVENTS = %w[assignment.* oauth.binding.* webhook.ping].freeze

  belongs_to :oauth_application, class_name: 'OauthApplication'

  validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 60 }
  validates :max_retries, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :url_must_be_https_when_enabled

  before_validation :ensure_defaults

  def as_admin_json(include_secret: false)
    data = {
      id: id,
      oauth_application_id: oauth_application_id,
      enabled: enabled,
      url: url,
      subscribed_events: Array(subscribed_events),
      timeout_seconds: timeout_seconds,
      max_retries: max_retries,
      custom_headers: custom_headers.to_h,
      last_success_at: last_success_at,
      last_failure_at: last_failure_at,
      has_signing_secret: signing_secret.present?,
      created_at: created_at,
      updated_at: updated_at
    }
    data[:signing_secret] = signing_secret if include_secret
    data
  end

  def renew_signing_secret!
    self.signing_secret = SecureRandom.hex(32)
  end

  def subscribed_to?(event_type)
    event = event_type.to_s
    Array(subscribed_events).any? do |pattern|
      pattern = pattern.to_s
      pattern == event ||
        (pattern.end_with?('.*') && event.start_with?(pattern.delete_suffix('.*')))
    end
  end

  private

  def ensure_defaults
    self.subscribed_events = DEFAULT_EVENTS if subscribed_events.blank?
    self.custom_headers = {} if custom_headers.nil?
    renew_signing_secret! if signing_secret.blank?
  end

  def url_must_be_https_when_enabled
    return unless enabled
    return if url.blank?

    uri = URI.parse(url)
    allow_http = Rails.env.development? && uri.host.in?(%w[localhost 127.0.0.1])
    return if uri.scheme == 'https' || allow_http

    errors.add(:url, 'must be an HTTPS URL (http allowed only for localhost in development)')
  rescue URI::InvalidURIError
    errors.add(:url, 'is not a valid URI')
  end
end
