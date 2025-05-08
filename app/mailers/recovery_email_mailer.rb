# frozen_string_literal: true

class RecoveryEmailMailer < ApplicationMailer
  # 主題可以考慮國際化 (I18n)
  default subject: 'Confirm your Recovery Email for AI ENGLISH'

  # 佈局可以指定，如果有的話，例如 'mailer_layout'
  # layout 'mailer_layout'

  # 發送後備Email確認指示
  # @param user [GeneralUser] 用戶對象
  # @param token [String] 用於確認的token
  def confirmation_instructions(user, token)
    @user = user
    @token = token
    # @confirmation_url = "YOUR_FRONTEND_CONFIRMATION_URL?confirmation_token=#{@token}"
    # 上述 URL 應指向前端處理Email確認的頁面，該頁面會將token發送到後端API進行驗證。
    # 例如：https://yourfrontend.com/auth/recovery-email-confirmation?token=YOUR_TOKEN
    # 暫時先定義一個佔位符，您需要根據您的前端路由來修改它。
    # **重要**: 這個URL的域名部分應該從環境變量或配置中獲取，而不是硬編碼。
    frontend_base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3001') # 假設前端在3001端口
    @confirmation_url = "#{frontend_base_url}/verify-recovery-email?token=#{@token}"

    # 確保 user.recovery_email 存在且有效
    if @user&.recovery_email.present?
      mail(to: @user.recovery_email,
           from: ENV.fetch('DEFAULT_MAILER_SENDER', 'aienglish-support@docai.net'), # 從環境變量獲取發件人
           subject: 'Confirm your Recovery Email for AI ENGLISH')
    else
      # 如果 recovery_email 無效或不存在，記錄錯誤並且不發送郵件
      Rails.logger.error("[RecoveryEmailMailer] Attempted to send confirmation to invalid recovery_email for user ID: #{@user&.id}")
      # 可以選擇不發送郵件，或者拋出一個錯誤，取決於您希望如何處理這種情況
      # 這裡我們選擇不發送，並讓調用方 (GeneralUser模型) 的 `deliver_later` 靜默失敗 (或被ActiveJob捕獲)
    end
  end
end
