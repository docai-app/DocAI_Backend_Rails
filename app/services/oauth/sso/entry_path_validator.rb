# frozen_string_literal: true

module Oauth
  module Sso
    # Allow only known AIEnglish Frontend assignment paths for SSO reopen.
    class EntryPathValidator
      PATHNAME_ALLOWED = %r{\A/(?:essay|comprehension|listening|speaking/conversation|speaking/essay|sentence_building|sentence_puzzle|speaking_pronunciation|talk_lab_speaking)/(?:upload|edit|grading|show)/[A-Za-z0-9_-]+\z}.freeze

      def self.normalize(raw)
        path = raw.to_s.strip
        return nil if path.blank?
        return nil if path.include?('://') || path.include?('..') || path.include?('\\')
        return nil unless path.start_with?('/')

        path = path.split('#').first.to_s
        uri = Addressable::URI.parse("https://invalid.local#{path}")
        pathname = uri.path.to_s
        return nil unless PATHNAME_ALLOWED.match?(pathname)

        query = Rack::Utils.parse_query(uri.query.to_s)
        query['embed'] = '1'
        "#{pathname}?#{query.to_query}"
      rescue Addressable::URI::InvalidURIError
        nil
      end
    end
  end
end
