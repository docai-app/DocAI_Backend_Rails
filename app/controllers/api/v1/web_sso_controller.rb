# frozen_string_literal: true

require 'uri'

module Api
  module V1
    class WebSsoController < ApiController
      include Devise::Controllers::Helpers

      PURPOSE = 'view_grading_result'

      before_action :authenticate_general_user!, only: :create

      # POST /api/v1/general_users/web_sso/tickets
      def create
        return render_student_only unless current_general_user.aienglish_role == 'student'

        grading = current_general_user.essay_gradings.includes(:essay_assignment).find(params.require(:essay_grading_id))
        WebSso::ResultDestination.path_for(grading)
        rate_limiter.check!(scope: :issue, identifier: current_general_user.id)

        ticket = ticket_store.issue(
          general_user_id: current_general_user.id,
          essay_grading_id: grading.id,
          purpose: PURPOSE
        )

        Rails.logger.info(
          "[WebSso#create] request_id=#{request.request_id} user_id=#{current_general_user.id} grading_id=#{grading.id}"
        )
        render json: {
          success: true,
          web_url: web_url(ticket),
          expires_in: WebSso::TicketStore::TTL_SECONDS
        }, status: :created
      rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound
        render json: {
          success: false,
          error: 'The requested grading result was not found.',
          error_code: 'GRADING_NOT_FOUND'
        }, status: :not_found
      rescue WebSso::ResultDestination::ResultNotAvailableError => e
        render json: { success: false, error: e.message, error_code: 'RESULT_NOT_AVAILABLE' }, status: :conflict
      rescue WebSso::RateLimiter::RateLimitedError => e
        render json: { success: false, error: e.message, error_code: 'WEB_SSO_RATE_LIMITED' }, status: :too_many_requests
      rescue WebSso::RateLimiter::UnavailableError, WebSso::TicketStore::UnavailableError => e
        render json: { success: false, error: e.message, error_code: 'WEB_SSO_UNAVAILABLE' }, status: :service_unavailable
      end

      # POST /api/v1/general_users/web_sso/exchange
      def exchange
        rate_limiter.check!(scope: :exchange, identifier: request.remote_ip)
        payload = ticket_store.consume(params.require(:ticket))
        raise WebSso::TicketStore::InvalidTicketError unless payload['purpose'] == PURPOSE

        user = GeneralUser.find(payload.fetch('general_user_id'))
        return render_student_only unless user.aienglish_role == 'student'
        return render_inactive_account unless user.active_for_authentication?

        grading = user.essay_gradings.includes(:essay_assignment).find(payload.fetch('essay_grading_id'))
        redirect_path = WebSso::ResultDestination.path_for(grading)

        sign_in(:general_user, user, store: false)
        Rails.logger.info(
          "[WebSso#exchange] request_id=#{request.request_id} user_id=#{user.id} grading_id=#{grading.id}"
        )
        render json: {
          success: true,
          redirect_path: redirect_path,
          user: { email: user.email }
        }, status: :ok
      rescue ActionController::ParameterMissing, KeyError, WebSso::TicketStore::InvalidTicketError
        render json: {
          success: false,
          error: 'This sign-in link is invalid, expired, or has already been used.',
          error_code: 'WEB_SSO_TICKET_INVALID'
        }, status: :unauthorized
      rescue ActiveRecord::RecordNotFound, WebSso::ResultDestination::ResultNotAvailableError
        render json: {
          success: false,
          error: 'This result is no longer available to this account.',
          error_code: 'RESULT_ACCESS_DENIED'
        }, status: :forbidden
      rescue WebSso::RateLimiter::RateLimitedError => e
        render json: { success: false, error: e.message, error_code: 'WEB_SSO_RATE_LIMITED' }, status: :too_many_requests
      rescue WebSso::RateLimiter::UnavailableError, WebSso::TicketStore::UnavailableError => e
        render json: { success: false, error: e.message, error_code: 'WEB_SSO_UNAVAILABLE' }, status: :service_unavailable
      end

      private

      def ticket_store
        @ticket_store ||= WebSso::TicketStore.new
      end

      def rate_limiter
        @rate_limiter ||= WebSso::RateLimiter.new
      end

      def web_url(ticket)
        base_url = ENV.fetch('AI_ENGLISH_STUDENT_WEB_URL', 'https://aienglish.docai.net')
        uri = URI.parse(base_url)
        production_web = uri.is_a?(URI::HTTPS) && uri.host == 'aienglish.docai.net' && uri.userinfo.nil?
        local_web = Rails.env.development? && %w[localhost 127.0.0.1].include?(uri.host) && uri.userinfo.nil?
        unless production_web || local_web
          raise WebSso::TicketStore::UnavailableError, 'The student website URL is not configured securely.'
        end

        uri.path = '/miniprogram/sso'
        uri.query = nil
        uri.fragment = "ticket=#{ticket}"
        uri.to_s
      rescue URI::InvalidURIError
        raise WebSso::TicketStore::UnavailableError, 'The student website URL is invalid.'
      end

      def render_student_only
        render json: {
          success: false,
          error: 'This sign-in link is only available for student accounts.',
          error_code: 'STUDENT_ACCOUNT_REQUIRED'
        }, status: :forbidden
      end

      def render_inactive_account
        render json: {
          success: false,
          error: 'This account is not available for authentication.',
          error_code: 'ACCOUNT_INACTIVE'
        }, status: :forbidden
      end
    end
  end
end
