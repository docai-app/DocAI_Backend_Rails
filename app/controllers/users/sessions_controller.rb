class Users::SessionsController < Devise::SessionsController
  respond_to :json

  private

  def respond_with(resource, _opts = {})
    resource.persisted? ? login_success : login_failed
    # render json: { success: true, message: "Logged.", user: resource }, status: :ok
  end

  def respond_to_on_destroy
    current_user ? log_out_success : log_out_failure
  end

  def log_out_success
    render json: { success: true, message: "Logged out." }, status: :ok
  end

  def log_out_failure
    render json: { success: false, message: "Logged out failure." }, status: :unauthorized
  end

  def login_success
    render json: { success: true, message: "Logged." }, status: :ok
  end

  def login_failed
    render json: { success: false, message: "Logged in failure." }, status: :unauthorized
  end
end
