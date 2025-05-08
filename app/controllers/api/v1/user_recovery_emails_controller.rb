# frozen_string_literal: true

module Api
  module V1
    class UserRecoveryEmailsController < ApiController # 確保繼承自您的API基類控制器
      before_action :authenticate_general_user! # 確保用戶已登錄

      # PUT /api/v1/me/recovery_email
      def update
        new_recovery_email = recovery_email_params[:recovery_email]

        # 基本的Email格式驗證 (雖然模型層也有，但控制器層快速檢查也是好的)
        if new_recovery_email.blank? || !(new_recovery_email =~ URI::MailTo::EMAIL_REGEXP)
          render json: { success: false, error: { message: 'Invalid email format.' } }, status: :bad_request
          return
        end

        # 檢查新舊Email是否相同且已確認，避免不必要的郵件發送
        if current_general_user.recovery_email == new_recovery_email && current_general_user.recovery_email_confirmed?
          render json: { success: true, data: { message: 'Recovery email is already set and confirmed to this address.' } },
                 status: :ok
          return
        end

        current_general_user.recovery_email = new_recovery_email
        current_general_user.recovery_email_confirmed_at = nil # 重要：新的或更改的Email需要重新確認
        current_general_user.recovery_confirmation_token = nil # 清除舊的token（如果有）
        current_general_user.recovery_confirmation_sent_at = nil

        if current_general_user.save # 保存 recovery_email，此處模型驗證會運行
          current_general_user.send_recovery_email_confirmation_instructions # 發送確認郵件
          render json: {
            success: true,
            data: { message: 'Recovery email updated. Please check your new recovery email inbox to confirm.' }
          }, status: :ok
        else
          render json: { success: false, errors: current_general_user.errors.full_messages },
                 status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("[UserRecoveryEmailsController#update] Error: #{e.message} - User: #{current_general_user&.id}")
        render json: { success: false, error: { message: 'An unexpected error occurred.' } },
               status: :internal_server_error
      end

      # DELETE /api/v1/me/recovery_email
      def destroy
        current_general_user.recovery_email = nil
        current_general_user.recovery_email_confirmed_at = nil
        current_general_user.recovery_confirmation_token = nil
        current_general_user.recovery_confirmation_sent_at = nil

        if current_general_user.save(validate: false) # 跳過驗證，因為我們只是清空字段
          render json: { success: true, data: { message: 'Recovery email has been removed.' } }, status: :ok
        else
          # 理論上清空字段不應該導致保存失敗，除非有其他回調等問題
          Rails.logger.error("[UserRecoveryEmailsController#destroy] Error saving user after clearing recovery email: #{current_general_user.errors.full_messages} - User: #{current_general_user&.id}")
          render json: { success: false, error: { message: 'Failed to remove recovery email.' } },
                 status: :internal_server_error
        end
      rescue StandardError => e
        Rails.logger.error("[UserRecoveryEmailsController#destroy] Error: #{e.message} - User: #{current_general_user&.id}")
        render json: { success: false, error: { message: 'An unexpected error occurred.' } },
               status: :internal_server_error
      end

      # POST /api/v1/me/recovery_email/resend_confirmation
      def resend_confirmation
        if current_general_user.recovery_email.blank?
          render json: { success: false, error: { message: 'No recovery email set to resend confirmation for.' } },
                 status: :bad_request
        elsif current_general_user.recovery_email_confirmed?
          render json: { success: false, error: { message: 'Recovery email is already confirmed.' } },
                 status: :unprocessable_entity
        elsif current_general_user.send_recovery_email_confirmation_instructions
          # 重新發送會生成新的token並更新發送時間
          render json: { success: true, data: { message: 'Confirmation email has been resent to your recovery email address.' } },
                 status: :ok
        else
          # send_recovery_email_confirmation_instructions 內部如果失敗（例如 recovery_email 格式不對導致mailer不發送），目前返回false
          # 但通常在調用此方法前，recovery_email 應該是已經保存且格式有效的
          render json: { success: false, error: { message: 'Failed to resend confirmation email. Please ensure your recovery email is valid.' } },
                 status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("[UserRecoveryEmailsController#resend_confirmation] Error: #{e.message} - User: #{current_general_user&.id}")
        render json: { success: false, error: { message: 'An unexpected error occurred.' } },
               status: :internal_server_error
      end

      private

      def recovery_email_params
        params.permit(:recovery_email) # 假設請求體是 { "recovery_email_details": { "recovery_email": "..." } }
        # 或者更簡單 params.permit(:recovery_email) 如果請求體直接是 { "recovery_email": "..." }
        # 根據您的前端請求結構調整
        # 暫定為 params.permit(:recovery_email)
      end
    end
  end
end
