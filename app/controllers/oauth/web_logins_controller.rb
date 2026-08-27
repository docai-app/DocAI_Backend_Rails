# frozen_string_literal: true

module Oauth
  # Top-level HTML form login for cross-origin SPAs (e.g. essay-admin → AS).
  # Cross-site fetch cannot set SameSite=Lax session cookies; a first-party
  # form POST to the AS can.
  class WebLoginsController < ApplicationController
    def create
      return_to = params[:return_to].to_s
      login_origin = params[:login_origin].to_s.chomp('/')
      email = params[:email].to_s.strip
      password = params[:password].to_s

      unless Oauth::ReturnToValidator.valid?(return_to)
        return render plain: 'Invalid return_to', status: :bad_request
      end

      unless valid_login_origin?(login_origin)
        return render plain: 'Invalid login_origin', status: :bad_request
      end

      user = GeneralUser.find_for_database_authentication(email: email)
      unless user&.valid_password?(password)
        return redirect_to login_error_url(login_origin, return_to, '邮箱或密码错误'),
                           allow_other_host: true
      end

      Oauth::SessionEstablisher.establish!(session, user)
      OauthAuditLog.record!(
        event: 'session_established',
        general_user: user,
        request: request,
        meta: { via: 'web_login' }
      )

      redirect_to return_to, allow_other_host: true
    end

    private

    def valid_login_origin?(origin)
      return false if origin.blank?

      uri = Addressable::URI.parse(origin)
      return false unless %w[http https].include?(uri.scheme)
      return false if uri.host.blank?

      allowed = [
        'localhost',
        '127.0.0.1',
        'essay-admin.docai.net',
        'aienglish-admin.docai.net',
        'konnec-ai.hospidocai.com',
        'app.konnec.ai'
      ]
      return true if allowed.include?(uri.host)
      return true if uri.host.end_with?('.vercel.app')
      return true if uri.host.end_with?('.hospidocai.com')

      false
    rescue Addressable::URI::InvalidURIError
      false
    end

    def login_error_url(login_origin, return_to, message)
      "#{login_origin}/login?return_to=#{CGI.escape(return_to)}&error=#{CGI.escape(message)}"
    end
  end
end
