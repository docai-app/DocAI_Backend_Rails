# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    respond_to :json
    before_action :get_tenent_when_login

    private

    def respond_with(resource, _opts = {})
      resource.persisted? ? login_success : login_failed
      # render json: { success: true, message: "Logged.", user: resource }, status: :ok
    end

    def respond_to_on_destroy
      current_user ? log_out_success : log_out_failure
    end

    def log_out_success
      render json: { success: true, message: 'Logged out.' }, status: :ok
    end

    def log_out_failure
      render json: { success: false, message: 'Logged out failure.' }, status: :unauthorized
    end

    def login_success
      render json: { success: true, message: 'Logged.' }, status: :ok
    end

    def login_failed
      render json: { success: false, message: 'Logged in failure.' }, status: :unauthorized
    end

    def get_tenent_when_login
      email = params[:user][:email]
      puts "email: #{email}"
      # Get email subdomain
      subdomain = email.split('@')[1].split('.')[0]
      puts "subdomain: #{subdomain}"
      tenantName = Utils.getTenantName(subdomain)
      puts "tenantName: #{tenantName}"
      Apartment::Tenant.switch!(tenantName)
    end
  end
end
