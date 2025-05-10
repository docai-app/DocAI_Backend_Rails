# frozen_string_literal: true

# app/mailers/custom_devise_mailer.rb
class CustomDeviseMailer < Devise::Mailer
  # helper :application # 通常 Devise::Mailer 已包含必要 helpers，如果 ApplicationHelper 不存在或不需要，可移除此行
  include Devise::Controllers::UrlHelpers # 確保郵件模板中 devise 相關的 URL helpers 可用
  default template_path: 'devise/mailer' # 指定Devise郵件模板的路徑

  # 覆寫 reset_password_instructions 方法
  def reset_password_instructions(record, token, opts = {})
    # record 是 GeneralUser 的實例
    # token 是生成的密碼重設token

    # 檢查是否有已驗證的後備Email
    if record.is_a?(GeneralUser) && record.recovery_email.present? && record.recovery_email_confirmed?
      # 如果有，則將密碼重設郵件發送到後備Email
      # 我們需要確保 Devise::Mailer 在生成郵件時使用這個新的 to 地址
      # Devise 的 mailer 通常會從 opts[:to] 或者 record.email 獲取收件人
      # 最直接的方式是修改 opts hash 或者直接在 mail() 調用中指定 :to
      # opts[:to] = record.recovery_email # 這種方式可能不一定被 super() 正確使用

      # 更可靠的方式是直接設置 headers for the mail
      # 或者在調用 super 之前，確保 record 對象的 email 屬性暫時指向 recovery_email
      # 但這比較 hacky。

      # 我們嘗試在 super 調用前修改 opts，如果不行，就需要更深入地看 Devise::Mailer 的 super 实现
      # 或者直接複製 Devise::Mailer#reset_password_instructions 的內容並修改
      # Rails.logger.info "[CustomDeviseMailer] Attempting to send reset password to RECOVERY EMAIL: #{record.recovery_email} for user #{record.id}"

      # 先調用 super 來獲取 Devise 生成的原始郵件對象
      # super 會處理 @token 的設置以及模板的選擇等
      message = super(record, token, opts)

      # 現在修改郵件對象的接收者和主題
      message.to = [record.recovery_email] # mail.to 期望一個數組或字符串
      message.subject = 'Reset your AI ENGLISH password (via Recovery Email)'

      # Rails.logger.info "[CustomDeviseMailer] Modified mail object: TO=#{message.to}, SUBJECT=#{message.subject}"
      message # 返回修改後的郵件對象

    else
      # 如果沒有已驗證的後備Email，或者記錄不是 GeneralUser (不太可能，但作為防禦)
      # 則執行Devise的默認行為 (發送到 record.email)
      # Rails.logger.info "[CustomDeviseMailer] Sending reset password to PRIMARY EMAIL: #{record.email} for user #{record.id}"
      super # 調用 Devise::Mailer 中的原始 reset_password_instructions 方法
    end
  end

  # 如果您還需要覆寫其他 Devise 郵件 (例如 confirmation_instructions, unlock_instructions)，
  # 也可以在這裡添加類似的邏輯。
end
