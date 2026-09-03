# frozen_string_literal: true

module Oauth
  # Minimal OIDC-style UserInfo for Phase 1 demos / partner integration.
  # Full OIDC (id_token / JWKS / Discovery) remains Phase 2.
  class UserinfoController < ApplicationController
    include Doorkeeper::Rails::Helpers

    before_action -> { doorkeeper_authorize! }

    # GET /oauth/userinfo
    def show
      user = GeneralUser.find_by(id: doorkeeper_token.resource_owner_id)
      unless user
        return render json: {
          error: 'invalid_token',
          error_description: 'Resource owner not found.'
        }, status: :unauthorized
      end

      scopes = doorkeeper_token.scopes
      payload = { sub: user.id.to_s }

      if scopes.exists?('profile')
        payload[:name] = user.nickname.presence || user.email
        payload[:nickname] = user.nickname
        payload[:updated_at] = user.updated_at&.iso8601
      end

      if scopes.exists?('email')
        payload[:email] = user.email
        payload[:email_verified] = false
      end

      render json: payload, status: :ok
    end
  end
end
