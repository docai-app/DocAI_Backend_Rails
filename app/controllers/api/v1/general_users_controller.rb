# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      before_action :authenticate_user!,
                    only: %i[show show_current_user show_purchase_history show_marketplace_items create update delete]
      def show
        @user = current_general_user
        render json: { success: true, user: @user }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_current_user
        @user = current_general_user
        render json: { success: true, user: @user.as_json(include: :energy) }, status: :ok
      end

      def show_purchase_history
        @user = current_general_user
        @purchases = @user.purchased_items
        render json: { success: true, purchases: @purchases }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_marketplace_items
        @user = current_general_user
        @user_marketplace_items = @user.user_marketplace_items
        render json: { success: true, user_marketplace_items: @user_marketplace_items }, status: :ok
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
