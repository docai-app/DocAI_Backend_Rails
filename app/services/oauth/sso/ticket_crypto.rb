# frozen_string_literal: true

module Oauth
  module Sso
    class TicketCrypto
      ACTIVE_KEY_VERSION = Integer(ENV.fetch('OAUTH_SSO_LAUNCH_KEY_VERSION', '1'))

      def self.derive_secret(client_id:, nonce:, launch_id:, key_version: ACTIVE_KEY_VERSION)
        key = derivation_key(key_version)
        data = ['aienglish-launch:v1', client_id.to_s, nonce.to_s, launch_id.to_s].join("\0")
        OpenSSL::HMAC.digest('SHA256', key, data)
      end

      def self.ticket_for(launch_id:, secret:)
        "#{launch_id}.#{Base64.urlsafe_encode64(secret, padding: false)}"
      end

      def self.parse_ticket(ticket)
        launch_id, secret_b64 = ticket.to_s.split('.', 2)
        raise Error.new('INVALID_REQUEST', 'Invalid ticket format.', http_status: 400) if launch_id.blank? || secret_b64.blank?

        secret = Base64.urlsafe_decode64(secret_b64)
        raise Error.new('INVALID_REQUEST', 'Invalid ticket format.', http_status: 400) if secret.bytesize < 32

        { launch_id: launch_id, secret: secret }
      rescue ArgumentError
        raise Error.new('INVALID_REQUEST', 'Invalid ticket format.', http_status: 400)
      end

      def self.derivation_key(version)
        configured = ENV["OAUTH_SSO_LAUNCH_DERIVATION_KEY_V#{version}"].presence ||
                     ENV['OAUTH_SSO_LAUNCH_DERIVATION_KEY'].presence ||
                     ENV['DEVISE_JWT_SECRET_KEY'].presence
        raise Error.new('PROVIDER_UNAVAILABLE', 'Launch key is not configured.', http_status: 503) if configured.blank?

        OpenSSL::Digest::SHA256.digest("#{configured}:v#{version}")
      end
    end
  end
end
