# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      def show
        User.find_by(id: params[:id])
        render json: { success: true, user: @user }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @user = User.new(user_params)
        if @user.save
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      end
    end
  end
end
