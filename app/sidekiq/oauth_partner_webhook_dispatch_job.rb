# frozen_string_literal: true

require 'net/http'

# Deliver a single OauthWebhookDelivery to Partner webhook URL.
class OauthPartnerWebhookDispatchJob
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: false

  def perform(delivery_id)
    delivery = OauthWebhookDelivery.find_by(id: delivery_id)
    return if delivery.blank?
    return if delivery.status == 'delivered' || delivery.status == 'dead_letter'

    application = delivery.oauth_application
    config = application&.webhook_config
    if config.blank? || config.url.blank? || config.signing_secret.blank?
      delivery.mark_attempt_failed!(
        http_status: nil,
        error: 'Webhook config missing url or signing_secret',
        max_retries: 0
      )
      return
    end

    body = delivery.payload.to_json
    timestamp = Time.current.to_i
    signature = Oauth::WebhookSigner.sign(
      secret: config.signing_secret,
      body: body,
      timestamp: timestamp
    )
    headers = Oauth::WebhookSigner.build_headers(
      event_type: delivery.event_type,
      delivery_id: delivery.id,
      timestamp: timestamp,
      signature: signature,
      custom_headers: config.custom_headers
    )

    response = post_json(config.url, body, headers, config.timeout_seconds)

    if response.code.to_i.between?(200, 299)
      delivery.mark_delivered!(http_status: response.code.to_i)
      config.update_columns(last_success_at: Time.current, updated_at: Time.current)
      return
    end

    if response.code.to_i == 410
      delivery.mark_attempt_failed!(
        http_status: 410,
        error: 'Partner returned 410 Gone',
        max_retries: 0
      )
      config.update_columns(last_failure_at: Time.current, updated_at: Time.current)
      return
    end

    delivery.mark_attempt_failed!(
      http_status: response.code.to_i,
      error: "HTTP #{response.code}: #{response.body.to_s.truncate(500)}",
      max_retries: config.max_retries
    )
    config.update_columns(last_failure_at: Time.current, updated_at: Time.current)

    schedule_retry(delivery) if delivery.status == 'failed'
  rescue StandardError => e
    delivery&.mark_attempt_failed!(
      http_status: nil,
      error: e.message,
      max_retries: config&.max_retries || 5
    )
    config&.update_columns(last_failure_at: Time.current, updated_at: Time.current)
    schedule_retry(delivery) if delivery&.status == 'failed'
    Rails.logger.warn("[OauthPartnerWebhookDispatchJob] #{e.class}: #{e.message}")
  end

  private

  def post_json(url, body, headers, timeout_seconds)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |k, v| request[k] = v }
    request.body = body
    http.request(request)
  end

  def schedule_retry(delivery)
    return if delivery.blank? || delivery.next_retry_at.blank?

    delay = [(delivery.next_retry_at - Time.current).to_i, 1].max
    OauthPartnerWebhookDispatchJob.perform_in(delay, delivery.id)
  end
end
