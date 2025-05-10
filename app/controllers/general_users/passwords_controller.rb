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
  # Devise 的默認 JSON 響應可能已經足夠，但如果需要也可以覆寫以統一格式
  # def update
  #   super do |resource|
  #     if resource.errors.empty?
  #       render json: { success: true, message: find_message(:updated_not_active, {}) }, status: :ok
  #       return
  #     else
  #       render json: { success: false, errors: resource.errors.full_messages }, status: :unprocessable_entity
  #       return
  #     end
  #   end
  # end
end
