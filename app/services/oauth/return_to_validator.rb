# frozen_string_literal: true

module Oauth
  module ReturnToValidator
    KNOWN_CALLBACK_PATHS = [
      '/api/auth/aienglish/callback',
      '/oauth/callback'
    ].freeze

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

    # Remove selected OIDC prompt values from an authorize URL so that after
    # forced re-login, the post-login return_to does not loop on prompt=login.
    def strip_prompt_values(url, values_to_remove)
      uri = Addressable::URI.parse(url.to_s)
      query = Rack::Utils.parse_query(uri.query.to_s)
      prompts = query['prompt'].to_s.split(/\s+/).reject(&:blank?)
      kept = prompts - Array(values_to_remove).map(&:to_s)
      if kept.empty?
        query.delete('prompt')
      else
        query['prompt'] = kept.join(' ')
      end
      uri.query = query.to_query.presence
      uri.to_s
    rescue Addressable::URI::InvalidURIError
      url.to_s
    end

    # Prefer login origin derived from the OAuth client's registered redirect_uri
    # (e.g. https://essay-admin.docai.net/api/... -> https://essay-admin.docai.net/login).
    # Falls back to AIENGLISH_WEB_ORIGIN for legacy / essay-checker web login.
    def frontend_login_url(return_to:, redirect_uri: nil, client_id: nil)
      base =
        login_origin_from_registered_redirect(redirect_uri: redirect_uri, client_id: client_id) ||
        configured_web_origin

      "#{base}/login?return_to=#{CGI.escape(return_to.to_s)}"
    end

    def login_origin_from_registered_redirect(redirect_uri:, client_id:)
      return nil if redirect_uri.blank?

      normalized = redirect_uri.to_s.strip
      return nil unless registered_redirect_uri?(normalized, client_id)

      uri = Addressable::URI.parse(normalized)
      return nil unless known_callback_path?(uri.path)
      return nil if uri.scheme.blank? || uri.host.blank?

      origin_from_uri(uri)
    rescue Addressable::URI::InvalidURIError
      nil
    end

    def registered_redirect_uri?(redirect_uri, client_id)
      return false if client_id.blank?

      client = OauthApplication.find_by(uid: client_id.to_s)
      return false unless client

      registered = client.redirect_uri.to_s.split(/\s+/).map(&:strip).reject(&:blank?)
      registered.include?(redirect_uri)
    end

    def known_callback_path?(path)
      path = path.to_s
      KNOWN_CALLBACK_PATHS.any? { |suffix| path == suffix || path.end_with?(suffix) }
    end

    def origin_from_uri(uri)
      port =
        if uri.port && !default_port?(uri.scheme, uri.port)
          ":#{uri.port}"
        else
          ''
        end
      "#{uri.scheme}://#{uri.host}#{port}"
    end

    def default_port?(scheme, port)
      (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80)
    end

    def configured_web_origin
      ENV.fetch('AIENGLISH_WEB_ORIGIN', 'http://localhost:3000').to_s.chomp('/')
    end
  end
end
