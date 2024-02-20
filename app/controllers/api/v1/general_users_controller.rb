# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      def show
        @user = current_user
        render json: { success: true, user: @user }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @user = GeneralUser.new(user_params)
        if @user.save
          @user.create_energy(value: 100)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      end

      private

      def user_params
        params.permit(:email, :password, :nickname, :phone, :date_of_birth, :sex)
      end
    end
  end
end
