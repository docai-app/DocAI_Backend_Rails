# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_user!, except: [:create]

      def index
        @users = User.all
        render json: { success: true, users: @users }, status: :ok
      end

      def show
        @user = User.find(params[:id])
        render json: { success: true, user: @user }, status: :ok
      end

      def show_current_user
        @user = current_user
        render json: { success: true, user: @user }, status: :ok
      end

      # def create
      #   @user = User.new(user_params)
      #   if @user.save
      #     render json: { success: true, user: @user }, status: :ok
      #   else
      #     render json: { success: false, errors: @user.errors }, status: :ok
      #   end
      # end

      # Only user can update his own profile
      def update
        @user = User.find(params[:id])
        if @user == current_user
          if @user.update(user_params)
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, errors: @user.errors }, status: :ok
          end
        else
          render json: { success: false, errors: 'You are not authorized to update this user' }, status: :ok
        end
      end

      # Write a method to update user his own profile
      def update_profile
        @user = current_user
        if @user.update(user_profile_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      end

      # Write a method to update user his own password
      def update_password
        @user = current_user
        if @user.update_with_password({ current_password: params[:current_password], password: params[:password],
                                        password_confirmation: params[:password_confirmation] })
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      end

      private

      def password_params
        params.require(:user).permit(:password, :password_confirmation, :current_password)
      end

      def user_profile_params
        params.require(:user).permit(:nickname, :phone, :position, :date_of_birth, :sex)
      end
    end
  end
end
