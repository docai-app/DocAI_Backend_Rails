# frozen_string_literal: true

module Api
  module Admin
    module V1
      class UsersController < AdminApiController
        include AdminAuthenticator

        def index
          Apartment::Tenant.switch!(params[:entity])
          @users = User.all
          render json: { success: true, users: @users }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def create
          Apartment::Tenant.switch!(params[:entity])
          @user = User.new(user_params)
          if @user.save
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, errors: @user.errors }, status: :ok
          end
        end

        private

        def user_params
          params.permit(:email, :password, :nickname, :phone, :position)
        end
      end
    end
  end
end
