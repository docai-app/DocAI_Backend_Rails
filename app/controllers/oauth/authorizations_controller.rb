# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    helper Oauth::AuthorizationsHelper

    before_action :ensure_client_enabled, only: %i[new create]
    before_action :ensure_pkce_s256, only: %i[new create]
    around_action :with_oauth_locale
    after_action :record_authorize_success, only: :create

    private

    def with_oauth_locale
      I18n.with_locale(:'zh-CN') { yield }
    end

    def ensure_client_enabled
      app = pre_auth&.client
      return if app.blank?
      return if !app.respond_to?(:enabled?) || app.enabled?

      OauthAuditLog.record!(
        event: 'authorize_disabled_client',
        application: find_application_record(app),
        request: request,
        meta: { client_id: app.try(:uid) }
      )

      render_oauth_error(
        error: 'unauthorized_client',
        description: 'Client is not enabled. Contact the administrator.'
      )
    end

    def ensure_pkce_s256
      challenge = params[:code_challenge].to_s
      method = params[:code_challenge_method].to_s
      return if challenge.present? && method == 'S256'

      render_oauth_error(
        error: 'invalid_request',
        description: 'PKCE with code_challenge_method=S256 is required for all clients.'
      )
    end

    def record_authorize_success
      return unless response.successful? || response.redirect?

      app = find_application_record(pre_auth&.client)
      user = current_resource_owner
      return if app.blank? || user.blank?

      OauthAuditLog.record!(
        event: 'authorize_success',
        application: app,
        general_user: user,
        request: request,
        meta: {
          client_id: app.uid,
          redirect_uri: pre_auth.try(:redirect_uri),
          scopes: pre_auth.try(:scopes).to_s
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[Oauth::AuthorizationsController] authorize audit failed: #{e.message}")
    end

    def find_application_record(app)
      return app if app.is_a?(OauthApplication)
      return nil if app.blank?

      OauthApplication.find_by(id: app.id) || OauthApplication.find_by(uid: app.uid)
    end

    def current_resource_owner
      return resource_owner if respond_to?(:resource_owner, true) && resource_owner.present?

      Oauth::SessionEstablisher.current(session)
    end

    def render_oauth_error(error:, description:)
      @error = error
      @error_description = description
      respond_to do |format|
        format.html { render 'doorkeeper/authorizations/error', status: :bad_request }
        format.json do
          render json: { error: error, error_description: description }, status: :bad_request
        end
        format.any do
          render json: { error: error, error_description: description }, status: :bad_request
        end
      end
    end
  end
end
