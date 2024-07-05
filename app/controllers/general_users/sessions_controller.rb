# frozen_string_literal: true

module GeneralUsers
  class SessionsController < Devise::SessionsController
    respond_to :json

    def create
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      respond_with resource, location: after_sign_in_path_for(resource)
    end

    private

    def respond_with(resource, _opts = {})
      puts "current tenant: #{Apartment::Tenant.current}"
      puts "resource: #{resource.inspect}"
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
  end
end
