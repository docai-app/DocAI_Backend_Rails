# frozen_string_literal: true

# Phase 1 OAuth AS configuration (Doorkeeper).
# See docs/oauth_oidc_identity_provider_design_2026_08_26_zh.md
Doorkeeper.configure do
  orm :active_record

  application_class 'OauthApplication'

  resource_owner_authenticator do
    prompts = request.params[:prompt].to_s.split(/\s+/).reject(&:blank?)
    force_login = prompts.include?('login')

    # OIDC prompt=login: clear AS session and send user to partner login.
    # Must return nil after redirect_to — a truthy return is treated as the owner.
    if force_login
      Oauth::SessionEstablisher.clear!(session)
      return_to = Oauth::ReturnToValidator.strip_prompt_values(request.original_url, %w[login])
      session[:oauth_return_to] = return_to if Oauth::ReturnToValidator.valid?(return_to)
      redirect_to Oauth::ReturnToValidator.frontend_login_url(
        return_to: return_to,
        redirect_uri: params[:redirect_uri],
        client_id: params[:client_id]
      ), allow_other_host: true
      nil
    else
      user = Oauth::SessionEstablisher.current(session)
      if user
        user
      else
        return_to = request.original_url
        session[:oauth_return_to] = return_to if Oauth::ReturnToValidator.valid?(return_to)
        redirect_to Oauth::ReturnToValidator.frontend_login_url(
          return_to: return_to,
          redirect_uri: params[:redirect_uri],
          client_id: params[:client_id]
        ), allow_other_host: true
        nil
      end
    end
  end

  # Built-in Doorkeeper application admin UI is disabled; use Admin API instead.
  admin_authenticator do
    head :forbidden
  end

  authorization_code_expires_in 10.minutes
  access_token_expires_in 1.hour

  use_refresh_token
  force_pkce
  hash_token_secrets
  hash_application_secrets

  grant_flows %w[authorization_code]

  default_scopes :openid, :profile, :email
  optional_scopes :offline_access

  allow_grant_flow_for_client do |_grant_flow, client|
    !client.respond_to?(:enabled?) || client.enabled?
  end

  skip_authorization do |_resource_owner, client|
    client.respond_to?(:trusted?) && client.trusted? && client.enabled?
  end
end
