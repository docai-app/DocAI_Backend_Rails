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

      # Embed runs inside a KonnecAI iframe (cross-site). HTTPS frontends must use
      # Secure + SameSite=None (+ Partitioned). Gating on Rails.env alone is wrong:
      # a development Rails serving https://essay-checker.docai.net would emit Lax
      # cookies that the browser never sends on iframe fetches → Devise 401.
      def self.cross_site_secure?(public_origin: nil)
        !http_public_origin?(public_origin)
      end

      def self.use_host_prefix?(public_origin: nil)
        return false if Rails.env.test?

        cross_site_secure?(public_origin: public_origin)
      end

      def self.set!(response:, token:, expires_at:, public_origin: nil)
        max_age = [(expires_at - Time.current).to_i, 1].max
        secure = cross_site_secure?(public_origin: public_origin)
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

        # Partitioned (CHIPS) is required for third-party iframe cookies in modern Chrome.
        # Not all Rack versions accept the flag on set_cookie — append manually.
        return unless secure && response.headers['Set-Cookie'].present?

        append_partitioned!(response, name)
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

      def self.append_partitioned!(response, cookie_name)
        raw = response.headers['Set-Cookie']
        cookies = case raw
                  when Array then raw
                  when String then raw.split(/[\n\r]+/).map(&:strip).reject(&:blank?)
                  else Array(raw)
                  end

        response.headers['Set-Cookie'] = cookies.map do |cookie|
          next cookie unless cookie.start_with?("#{cookie_name}=")
          next cookie if cookie.match?(/;\s*Partitioned\b/i)

          "#{cookie}; Partitioned"
        end
      end
      private_class_method :append_partitioned!
    end
  end
end
