# frozen_string_literal: true

module Oauth
  module ReturnToValidator
    module_function

    # Only allow returning to this app's /oauth/authorize (prevent open redirect).
    def valid?(url)
      return false if url.blank?

      uri = Addressable::URI.parse(url.to_s)
      return false unless uri.path.to_s.start_with?('/oauth/authorize')

      allowed_hosts = [
        ENV['OAUTH_ISSUER_HOST'].presence,
        ENV['APP_HOST'].presence,
        'localhost',
        '127.0.0.1',
        'docai-dev.m2mda.com',
        'docai.m2mda.com'
      ].compact

      host = uri.host.presence || 'localhost'
      allowed_hosts.include?(host)
    rescue Addressable::URI::InvalidURIError
      false
    end

    def frontend_login_url(return_to:)
      base = ENV.fetch('AIENGLISH_WEB_ORIGIN', 'http://localhost:3000').to_s.chomp('/')
      "#{base}/login?return_to=#{CGI.escape(return_to.to_s)}"
    end
  end
end
