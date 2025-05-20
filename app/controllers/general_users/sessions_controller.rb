# frozen_string_literal: true

module GeneralUsers
  class SessionsController < Devise::SessionsController
    respond_to :json

    def create
      self.resource = warden.authenticate(auth_options)

      if resource && warden.authenticated?(resource_name)
        sign_in(resource_name, resource)

        if resource.persisted?
          strategy_name = if warden.winning_strategy
                            warden.winning_strategy.class.name.demodulize.underscore.sub(/_authenticatable$/, '')
                          else
                            'unknown'
                          end

          ahoy.authenticate(resource) if resource.persisted?

          ahoy.track 'GeneralUser Signed In', { strategy: strategy_name }
          Rails.logger.info "[SessionsController] Tracked 'GeneralUser Signed In' for general_user ID: #{resource.id}, strategy: #{strategy_name}"
        end

        respond_with resource, location: after_sign_in_path_for(resource)
      else
        login_failed
      end
    end

    private

    def respond_with(resource, _opts = {})
      resource && resource.persisted? ? login_success : login_failed
    end

    def respond_to_on_destroy
      if warden.authenticated?(resource_name)
        log_out_failure
      else
        log_out_success
      end
    end

    def log_out_success
      render json: { success: true, message: 'Logged out.' }, status: :ok
    end

    def log_out_failure
      render json: { success: false, message: 'Logged out failure.' }, status: :unauthorized
    end

    def login_success
      render json: {
        success: true,
        message: 'Logged in successfully.'
      }, status: :ok
    end

    def login_failed
      render json: { success: false, error: 'Invalid email or password.' }, status: :unauthorized
    end
  end
end
