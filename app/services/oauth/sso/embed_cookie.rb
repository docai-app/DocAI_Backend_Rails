# frozen_string_literal: true

module Oauth
  module Sso
    class EmbedCookie
      COOKIE_NAME_HOST = '__Host-aienglish_embed'
      COOKIE_NAME_DEV = 'aienglish_embed'

      def self.cookie_name
        use_host_prefix? ? COOKIE_NAME_HOST : COOKIE_NAME_DEV
      end

      # When AIENGLISH_PUBLIC_ORIGIN is http:// (e.g. local essay-checker against
      # a remote Rails), browsers reject Secure / __Host- cookies on that page.
      def self.http_public_origin?
        ENV.fetch('AIENGLISH_PUBLIC_ORIGIN', '').to_s.start_with?('http://')
      end

      def self.use_host_prefix?
        !Rails.env.development? && !Rails.env.test? && !http_public_origin?
      end

      def self.set!(response:, token:, expires_at:)
        max_age = [(expires_at - Time.current).to_i, 1].max
        secure = (use_host_prefix? || Rails.env.production?) && !http_public_origin?

        response.set_cookie(
          cookie_name,
          value: token,
          path: '/',
          secure: secure,
          httponly: true,
          same_site: secure ? :none : :lax,
          max_age: max_age,
          expires: expires_at
        )

        # Partitioned is not in all Rack versions; append manually when using Host cookie.
        return unless use_host_prefix? && response.headers['Set-Cookie'].present?

        response.headers['Set-Cookie'] = Array(response.headers['Set-Cookie']).map do |cookie|
          next cookie unless cookie.start_with?("#{COOKIE_NAME_HOST}=")
          next cookie if cookie.include?('Partitioned')

          "#{cookie}; Partitioned"
        end
      end

      def self.clear!(response)
        response.delete_cookie(cookie_name, path: '/')
      end

      def self.read(request)
        request.cookies[cookie_name].presence ||
          request.cookies[COOKIE_NAME_HOST].presence ||
          request.cookies[COOKIE_NAME_DEV].presence
      end

      def self.parse(token)
        session_id, secret_b64 = token.to_s.split('.', 2)
        return nil if session_id.blank? || secret_b64.blank?

        secret = Base64.urlsafe_decode64(secret_b64)
        { session_id: session_id, secret: secret }
      rescue ArgumentError
        nil
      end
    end
  end
end
