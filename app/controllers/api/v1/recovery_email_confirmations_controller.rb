# frozen_string_literal: true

module Api
  module V1
    class RecoveryEmailConfirmationsController < ApiController
      def show
        token = params[:token]

        if token.blank?
          render json: { success: false, error: { message: 'Confirmation token is missing.' } }, status: :bad_request
          return
        end

        # 根據 recovery_confirmation_token 查找用戶
        # 由於 token 應該是唯一的，所以用 find_by 而不是 where
        user = GeneralUser.find_by(recovery_confirmation_token: token)

        if user.nil?
          render json: { success: false, error: { message: 'Invalid confirmation token.' } }, status: :not_found
        elsif user.recovery_confirmation_token_expired?
          # 在這裡，您可以選擇讓用戶重新發送確認郵件
          # 例如，前端可以引導用戶到某個頁面，觸發重新發送的API
          render json: {
            success: false,
            error: {
              message: 'Confirmation token has expired. Please request a new confirmation email.',
              code: 'TOKEN_EXPIRED' # 可選的錯誤碼供前端識別
            }
          }, status: :unprocessable_entity # 422 更合適，因為請求本身是可理解的，但語義上無效
        elsif user.confirm_recovery_email_by_token(token)
          render json: { success: true, data: { message: 'Your recovery email has been successfully confirmed.' } },
                 status: :ok
        # 確認成功
        # 前端通常會顯示成功消息，並可能引導用戶登錄或到個人資料頁
        else
          # 理論上，如果 token 匹配且未過期，confirm_recovery_email_by_token 內部不應該失敗
          # 但以防萬一，或者如果 confirm_recovery_email_by_token 內部有其他驗證可能失敗
          render json: { success: false, error: { message: 'Failed to confirm recovery email. Please try again or contact support.' } },
                 status: :unprocessable_entity
        end
      rescue StandardError => e
        # 捕獲任何意外錯誤
        Rails.logger.error("[RecoveryEmailConfirmationsController] Error during recovery email confirmation: #{e.message} - Token: #{token} - Backtrace: #{e.backtrace.join("\n")}")
        render json: { success: false, error: { message: 'An unexpected error occurred. Please try again later.' } },
               status: :internal_server_error
      end
    end
  end
end
