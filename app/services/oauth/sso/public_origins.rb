# frozen_string_literal: true

module Oauth
  module Sso
    # Essay-checker frontend origins used for enterUrl / post-enter redirects.
    #
    # AIENGLISH_PUBLIC_ORIGINS — comma/space-separated allowlist; **first item is the default**
    #   when launch omits providerOrigin (also used by webhook deep links).
    #
    # Legacy fallbacks (only if PUBLIC_ORIGINS is empty):
    #   AIENGLISH_PUBLIC_ORIGIN → FRONTEND_URL → AIENGLISH_WEB_ORIGIN → FALLBACK
    class PublicOrigins
      FALLBACK = 'https://docai.m2mda.com'

      def self.allowed_list
        from_env = parse_list(ENV['AIENGLISH_PUBLIC_ORIGINS'])
        return from_env if from_env.any?

        # Legacy single-origin envs when PUBLIC_ORIGINS is unset.
        legacy = [
          ENV['AIENGLISH_PUBLIC_ORIGIN'],
          ENV['FRONTEND_URL'],
          ENV['AIENGLISH_WEB_ORIGIN'],
          FALLBACK
        ].filter_map { |raw| normalize_origin(raw) }

        legacy.uniq
      end

      def self.default
        allowed_list.first || FALLBACK
      end

      def self.allowed?(origin)
        return false if origin.blank?

        normalized = OriginValidator.normalize(origin)
        allowed_list.include?(normalized)
      rescue URI::InvalidURIError
        false
      end

      # Resolve launch provider origin. Blank → default. Otherwise must be allowlisted.
      def self.resolve!(requested)
        return default if requested.blank?

        unless OriginValidator.exact_origin?(requested)
          raise Error.new('INVALID_PROVIDER_ORIGIN', 'providerOrigin must be an exact origin.', http_status: 400)
        end

        normalized = OriginValidator.normalize(requested)
        unless allowed?(normalized)
          raise Error.new(
            'INVALID_PROVIDER_ORIGIN',
            'providerOrigin is not registered for this AIEnglish environment.',
            http_status: 400
          )
        end

        normalized
      end

      def self.http?(origin)
        origin.to_s.start_with?('http://')
      end

      def self.parse_list(raw)
        raw.to_s
           .split(/[\s,]+/)
           .map(&:strip)
           .reject(&:blank?)
           .filter_map { |item| normalize_origin(item) }
           .uniq
      end
      private_class_method :parse_list

      def self.normalize_origin(raw)
        candidate = raw.to_s.strip.chomp('/')
        return nil if candidate.blank?
        return nil unless OriginValidator.exact_origin?(candidate)

        OriginValidator.normalize(candidate)
      rescue URI::InvalidURIError
        nil
      end
      private_class_method :normalize_origin
    end
  end
end
