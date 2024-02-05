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

        def lock_user
          Apartment::Tenant.switch!(params[:entity])
          @user = User.find_by(email: params[:email])
          puts @user.inspect
          if @user.update(locked_at: Time.current)
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, error: 'User not found' }, status: :ok
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def unlock_user
          Apartment::Tenant.switch!(params[:entity])
          @user = User.find_by(email: params[:email])
          if @user.update(locked_at: nil, failed_attempts: 0, unlock_token: nil)
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, error: 'User not found' }, status: :ok
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        private

        def user_params
          params.permit(:email, :password, :nickname, :phone, :position)
        end
      end
    end
  end
end
