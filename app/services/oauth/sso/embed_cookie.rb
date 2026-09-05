# frozen_string_literal: true

module Oauth
  module Sso
    class EmbedCookie
      COOKIE_NAME_HOST = '__Host-aienglish_embed'
      COOKIE_NAME_DEV = 'aienglish_embed'

      def self.cookie_name(public_origin: nil)
        use_host_prefix?(public_origin: public_origin) ? COOKIE_NAME_HOST : COOKIE_NAME_DEV
      end

      # When the essay-checker page is http:// (e.g. local frontend against remote Rails),
      # browsers reject Secure / __Host- cookies on that page.
      def self.http_public_origin?(public_origin = nil)
        origin = public_origin.presence || PublicOrigins.default
        PublicOrigins.http?(origin)
      end

      def self.use_host_prefix?(public_origin: nil)
        !Rails.env.development? && !Rails.env.test? && !http_public_origin?(public_origin)
      end

      def self.set!(response:, token:, expires_at:, public_origin: nil)
        max_age = [(expires_at - Time.current).to_i, 1].max
        secure = (use_host_prefix?(public_origin: public_origin) || Rails.env.production?) &&
                 !http_public_origin?(public_origin)
        name = cookie_name(public_origin: public_origin)

        response.set_cookie(
          name,
          value: token,
          path: '/',
          secure: secure,
          httponly: true,
          same_site: secure ? :none : :lax,
          max_age: max_age,
          expires: expires_at
        )

        # Partitioned is not in all Rack versions; append manually when using Host cookie.
        return unless use_host_prefix?(public_origin: public_origin) && response.headers['Set-Cookie'].present?

        response.headers['Set-Cookie'] = Array(response.headers['Set-Cookie']).map do |cookie|
          next cookie unless cookie.start_with?("#{COOKIE_NAME_HOST}=")
          next cookie if cookie.include?('Partitioned')

          "#{cookie}; Partitioned"
        end
      end

      def self.clear!(response)
        response.delete_cookie(COOKIE_NAME_HOST, path: '/')
        response.delete_cookie(COOKIE_NAME_DEV, path: '/')
      end

      def self.read(request)
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
