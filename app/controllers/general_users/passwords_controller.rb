# frozen_string_literal: true

# app/controllers/general_users/passwords_controller.rb
class GeneralUsers::PasswordsController < Devise::PasswordsController
  # 讓此控制器能夠響應JSON請求
  respond_to :json

  # POST /resource/password
  # (即 POST /general_users/password)
  def create
    # 調用Devise的標準方法來查找用戶並發送重設密碼指示
    # resource_class 是 GeneralUser
    # resource_params 是 { email: "provided_email@example.com" }
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    if successfully_sent?(resource)
      # 如果郵件（嘗試）成功發送
      # Devise 默認會調用 respond_with resource, location: after_sending_reset_password_instructions_path_for(resource_name)
      # 對於JSON API，我們需要返回一個明確的JSON響應
      # find_message(:send_instructions) 會從Devise的I18n文件中獲取標準消息
      render json: {
        success: true,
        message: find_message(:send_instructions, {}) # 第二個參數是 options hash
      }, status: :ok
    else
      # 如果由於某些原因（例如，用戶不存在，但Devise通常不會在這裡報錯以防枚舉用戶）
      # 或者在send_reset_password_instructions內部發生錯誤且resource.errors被填充
      # （注意：Devise為了安全，即使email不存在，通常也會模擬成功發送）
      # 所以，這裡的錯誤情況主要是針對resource.errors被填充的情況，例如Email格式不對（雖然通常在前端或模型驗證）
      render json: {
        success: false,
        errors: resource.errors.any? ? resource.errors.full_messages : [find_message(:not_found, {})] # 如果沒有具體錯誤，返回not_found消息
      }, status: :unprocessable_entity
    end
  end

  # PUT /resource/password
  # (即 PUT /general_users/password)
  # 這個方法用於用戶提交新密碼時
  def update
    # 調用 Devise 的標準 update 方法
    # self.resource 會被 Devise 的 super 方法設置為當前 GeneralUser 實例
    super do |resource|
      # resource 是 Devise PasswordsController 嘗試更新的 GeneralUser 實例
      # 檢查密碼是否已成功更新 (resource.errors.empty? 是一個好指標)
      # 並且 resource (用戶) 確實存在且可操作
      if resource.errors.empty? && resource.persisted?
        # 使用 ahoy.track 方法而不是 Ahoy.track 類方法
        # 明確指定用戶對象作為選項
        ahoy.track 'Password Changed', { time: Time.current, user: resource }

        Rails.logger.info "[PasswordsController] Tracked 'Password Changed' for general_user ID: #{resource.id}"

        # Devise 的默認成功響應處理 (如果 Devise.sign_in_after_reset_password 為 true，用戶會被登入)
        # find_message(:updated_not_active) -> "Your password has been changed successfully."
        # find_message(:updated) -> "Your password has been changed successfully. You are now signed in."
        # 我們可以根據是否自動登入返回不同的消息，或者統一返回 "updated_not_active"
        # 以符合 API 行為（通常重設密碼後不一定立即返回包含 session 的用戶對象）
        render json: { success: true, message: find_message(:updated_not_active, {}) }, status: :ok
        return # 確保後續 Devise 默認的 respond_with 不會再次執行
      else
        # 如果 resource.errors 不為空，表示更新失敗
        render json: { success: false, errors: resource.errors.full_messages }, status: :unprocessable_entity
        return # 同上
      end
    end
    # 如果 super 沒有調用 block (例如 Devise 內部邏輯直接 render 或 redirect 了，雖然對於 API 模式較少見)
    # 則這裡的代碼可能不會執行。但 Devise::PasswordsController#update 通常會 yield resource。
    # 如果 resource 在 super 調用後沒有被賦值或者 block 未執行，需要檢查 Devise 版本和行為。
    # 通常, 如果 block 沒被執行，意味著 Devise 已經處理了響應 (例如 token 無效時)。
    # 此時 self.resource 可能未被正確設置，或者已經被渲染。
    # 檢查 self.resource 是否有效以及是否已經執行過渲染
    return if performed? || self.resource.nil?

    # 這種情況通常是 token 無效等 Devise 內部處理的錯誤
    # Devise 會設置 resource.errors
    render json: { success: false, errors: self.resource.errors.full_messages }, status: :unprocessable_entity
  end
end
