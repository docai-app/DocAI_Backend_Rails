# frozen_string_literal: true

module Oauth
  # Demo/testing: revoke all grants & tokens for the current user + client,
  # mark partner account link revoked, and clear the AS session.
  class RevokeBindingsController < ApplicationController
    include Doorkeeper::Rails::Helpers

    before_action -> { doorkeeper_authorize! }

    # POST /oauth/revoke_binding
    def create
      user_id = doorkeeper_token.resource_owner_id
      app_id = doorkeeper_token.application_id
      application = OauthApplication.find_by(id: app_id)
      user = GeneralUser.find_by(id: user_id)

      links = OauthPartnerAccountLink.active.where(
        oauth_application_id: app_id,
        general_user_id: user_id
      ).to_a

      revoke_all_for!(user_id, app_id)
      OauthPartnerAccountLink.revoke_for!(
        application_id: app_id,
        general_user_id: user_id,
        reason: 'user_revoke_binding'
      )
      Oauth::SessionEstablisher.clear!(session)

      OauthAuditLog.record!(
        event: 'revoke_binding',
        general_user: user,
        application: application,
        request: request
      )

      links.each do |link|
        link.reload
        Oauth::WebhookDispatcher.enqueue_binding_revoked(link, reason: 'user_revoke_binding')
      end

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
