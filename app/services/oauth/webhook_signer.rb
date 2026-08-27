# frozen_string_literal: true

module Oauth
  # Build signed webhook envelope and HTTP headers for Partner delivery.
  class WebhookSigner
    HEADER_EVENT = 'X-AIEnglish-Event'
    HEADER_DELIVERY = 'X-AIEnglish-Delivery-Id'
    HEADER_TIMESTAMP = 'X-AIEnglish-Timestamp'
    HEADER_SIGNATURE = 'X-AIEnglish-Signature'
    USER_AGENT = 'AIEnglish-Webhook/1.0'

    def self.sign(secret:, body:, timestamp: Time.current.to_i)
      payload = "#{timestamp}.#{body}"
      digest = OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, payload)
      "sha256=#{digest}"
    end

    def self.build_headers(event_type:, delivery_id:, timestamp:, signature:, custom_headers: {})
      headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => USER_AGENT,
        HEADER_EVENT => event_type.to_s,
        HEADER_DELIVERY => delivery_id.to_s,
        HEADER_TIMESTAMP => timestamp.to_s,
        HEADER_SIGNATURE => signature
      }
      custom_headers.to_h.each do |key, value|
        next if key.blank? || value.blank?
        next if key.to_s.downcase.start_with?('x-aienglish-')

        headers[key.to_s] = value.to_s
      end
      headers
    end

    def self.build_envelope(id:, type:, client_id:, data:, created_at: Time.current)
      {
        id: id,
        type: type,
        created_at: created_at.utc.iso8601,
        api_version: '2026-08-27',
        client_id: client_id,
        data: data
      }
    end
  end
end
