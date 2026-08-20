# frozen_string_literal: true

module Api
  module V1
    class WechatMiniprogramController < ApiController
      include Devise::Controllers::Helpers

      before_action :authenticate_general_user!, only: %i[bind binding unbind]

      # POST /api/v1/general_users/wechat_miniprogram/bind
      def bind
        code = params.require(:code)
        outcome = current_general_user.bind_with_wechat_code!(
          code,
          nickname: params[:nickname],
          avatar_url: params[:avatar_url]
        )

        if outcome[:ok]
          render json: { success: true, binding: outcome[:binding] }, status: :ok
        else
          render json: {
            success: false,
            error: outcome[:message],
            error_code: outcome[:error_code]
          }, status: bind_failure_http_status(outcome[:error_code])
        end
      rescue ActionController::ParameterMissing
        render json: { success: false, error: 'code is required.', error_code: 'INVALID_REQUEST' }, status: :bad_request
      rescue WechatMiniprogram::AuthService::ConfigurationError => e
        render json: { success: false, error: e.message, error_code: 'WECHAT_CONFIG_ERROR' }, status: :service_unavailable
      rescue WechatMiniprogram::AuthService::WechatError => e
        render json: { success: false, error: e.message, error_code: 'WECHAT_CODE_INVALID' }, status: :unauthorized
      rescue RestClient::Exception => e
        Rails.logger.error("[WechatMiniprogram#bind] #{e.class}: #{e.message}")
        render json: { success: false, error: 'WeChat service unavailable.', error_code: 'WECHAT_UPSTREAM_ERROR' },
               status: :bad_gateway
      end

      # POST /api/v1/general_users/wechat_miniprogram/login
      def login
        code = params.require(:code)
        session_data = WechatMiniprogram::AuthService.jscode2session(code)
        openid = session_data['openid'].to_s
        if openid.blank?
          return render json: { success: false, error: 'Missing openid from WeChat.', error_code: 'WECHAT_CODE_INVALID' },
                        status: :unauthorized
        end

        user = GeneralUser.find_by_wechat_miniprogram(
          app_id: WechatMiniprogram::AuthService.app_id,
          openid: openid
        )
        unless user
          return render json: {
            success: false,
            error: 'WeChat is not linked to an account. Sign in with email and bind first.',
            error_code: 'WECHAT_NOT_BOUND'
          }, status: :unauthorized
        end

        unless user.active_for_authentication?
          return render json: { success: false, error: 'Account is not available for authentication.', error_code: 'ACCOUNT_INACTIVE' },
                        status: :forbidden
        end

        user.touch_wechat_miniprogram_last_login!
        sign_in(:general_user, user, store: false)
        render json: { success: true, message: 'Logged in successfully.' }, status: :ok
      rescue ActionController::ParameterMissing
        render json: { success: false, error: 'code is required.', error_code: 'INVALID_REQUEST' }, status: :bad_request
      rescue WechatMiniprogram::AuthService::ConfigurationError => e
        render json: { success: false, error: e.message, error_code: 'WECHAT_CONFIG_ERROR' }, status: :service_unavailable
      rescue WechatMiniprogram::AuthService::WechatError => e
        render json: { success: false, error: e.message, error_code: 'WECHAT_CODE_INVALID' }, status: :unauthorized
      rescue RestClient::Exception => e
        Rails.logger.error("[WechatMiniprogram#login] #{e.class}: #{e.message}")
        render json: { success: false, error: 'WeChat service unavailable.', error_code: 'WECHAT_UPSTREAM_ERROR' },
               status: :bad_gateway
      end

      # GET /api/v1/general_users/wechat_miniprogram/binding
      def binding
        if current_general_user.wechat_miniprogram_bound?
          render json: { success: true, bound: true, binding: current_general_user.wechat_miniprogram_binding_for_response },
                 status: :ok
        else
          render json: { success: true, bound: false, binding: nil }, status: :ok
        end
      end

      # DELETE /api/v1/general_users/wechat_miniprogram/binding
      #
      # A fresh wx.login code proves that the authenticated learner still
      # controls the WeChat identity linked to this account. Unbinding keeps
      # the current JWT valid and removes no other GeneralUser metadata.
      def unbind
        code = params.require(:code)
        session_data = WechatMiniprogram::AuthService.jscode2session(code)
        openid = session_data['openid'].to_s
        if openid.blank?
          return render json: {
            success: false,
            error: 'Missing openid from WeChat.',
            error_code: 'WECHAT_CODE_INVALID'
          }, status: :unauthorized
        end

        outcome = current_general_user.unbind_wechat_miniprogram!(
          app_id: WechatMiniprogram::AuthService.app_id,
          openid:
        )

        if outcome[:ok]
          render json: { success: true, bound: false, binding: nil }, status: :ok
        else
          render json: {
            success: false,
            error: outcome[:message],
            error_code: outcome[:error_code]
          }, status: :forbidden
        end
      rescue ActionController::ParameterMissing
        render json: {
          success: false,
          error: 'code is required.',
          error_code: 'WECHAT_CODE_REQUIRED'
        }, status: :bad_request
      rescue WechatMiniprogram::AuthService::ConfigurationError => e
        render json: {
          success: false,
          error: e.message,
          error_code: 'WECHAT_CONFIG_ERROR'
        }, status: :service_unavailable
      rescue WechatMiniprogram::AuthService::WechatError => e
        render json: {
          success: false,
          error: e.message,
          error_code: 'WECHAT_CODE_INVALID'
        }, status: :unauthorized
      rescue RestClient::Exception => e
        Rails.logger.error("[WechatMiniprogram#unbind] #{e.class}: #{e.message}")
        render json: {
          success: false,
          error: 'WeChat service unavailable.',
          error_code: 'WECHAT_UPSTREAM_ERROR'
        }, status: :bad_gateway
      end

      private

      def bind_failure_http_status(error_code)
        case error_code
        when 'WECHAT_ALREADY_BOUND', 'WECHAT_OPENID_CONFLICT'
          :conflict
        when 'WECHAT_CODE_INVALID'
          :unauthorized
        else
          :unprocessable_entity
        end
      end
    end
  end
end
