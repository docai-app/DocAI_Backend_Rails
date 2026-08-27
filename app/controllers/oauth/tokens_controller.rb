# frozen_string_literal: true

module Oauth
  # Token endpoint inherits Doorkeeper behavior.
  # Records audit + upserts partner link skeleton (external_user_id may be filled later).
  class TokensController < Doorkeeper::TokensController
    after_action :record_token_audit, only: :create

    private

    def record_token_audit
      return unless response.successful?

      token = authorize_response.try(:token)
      return if token.blank?

      application = OauthApplication.find_by(id: token.application_id)
      user = GeneralUser.find_by(id: token.resource_owner_id)
      return if application.blank? || user.blank?

      grant_type = params[:grant_type].to_s
      event = grant_type == 'refresh_token' ? 'token_refresh' : 'token_issued'

      OauthAuditLog.record!(
        event: event,
        application: application,
        general_user: user,
        request: request,
        meta: { grant_type: grant_type, scopes: token.scopes.to_s }
      )

      OauthPartnerAccountLink.upsert_active!(
        application: application,
        general_user: user,
        external_site: application.homepage_url,
        meta: { via: 'token_endpoint', grant_type: grant_type }
      )
    rescue StandardError => e
      Rails.logger.warn("[Oauth::TokensController] audit failed: #{e.message}")
    end
  end
end
