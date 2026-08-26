# frozen_string_literal: true

module Oauth
  # Demo/testing: revoke all grants & tokens for the current user + client,
  # and clear the AS session so the consent screen appears again.
  class RevokeBindingsController < ApplicationController
    include Doorkeeper::Rails::Helpers

    before_action -> { doorkeeper_authorize! }

    # POST /oauth/revoke_binding
    def create
      user_id = doorkeeper_token.resource_owner_id
      app_id = doorkeeper_token.application_id

      revoke_all_for!(user_id, app_id)
      Oauth::SessionEstablisher.clear!(session)

      OauthAuditLog.record!(
        event: 'revoke_binding',
        general_user: GeneralUser.find_by(id: user_id),
        application: OauthApplication.find_by(id: app_id),
        request: request
      )

      render json: {
        success: true,
        message: 'OAuth binding revoked. You can authorize again.'
      }, status: :ok
    end

    private

    def revoke_all_for!(user_id, app_id)
      Doorkeeper::AccessToken.where(
        resource_owner_id: user_id,
        application_id: app_id,
        revoked_at: nil
      ).find_each(&:revoke)

      Doorkeeper::AccessGrant.where(
        resource_owner_id: user_id,
        application_id: app_id,
        revoked_at: nil
      ).find_each(&:revoke)
    rescue StandardError => e
      Rails.logger.warn("[Oauth::RevokeBindingsController] revoke failed: #{e.message}")
      raise
    end
  end
end
