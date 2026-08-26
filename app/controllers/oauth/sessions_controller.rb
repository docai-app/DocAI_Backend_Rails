# frozen_string_literal: true

module Oauth
  # Bridge: SPA holds Devise JWT → establish HttpOnly AS session for /oauth/authorize.
  class SessionsController < ApplicationController
    before_action :authenticate_general_user!

    # POST /oauth/session
    def create
      user = current_general_user
      Oauth::SessionEstablisher.establish!(session, user)
      OauthAuditLog.record!(
        event: 'session_established',
        general_user: user,
        request: request
      )

      return_to = params[:return_to].presence || session[:oauth_return_to]
      payload = { success: true, message: 'OAuth session established.' }
      if return_to.present? && Oauth::ReturnToValidator.valid?(return_to)
        payload[:return_to] = return_to
      end

      render json: payload, status: :ok
    end

    # DELETE /oauth/session
    def destroy
      Oauth::SessionEstablisher.clear!(session)
      render json: { success: true, message: 'OAuth session cleared.' }, status: :ok
    end
  end
end
