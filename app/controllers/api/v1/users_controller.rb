# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApiController
      before_action :authenticate_user!, except: [:create]

      def index
        @users = User.all.page(params[:page])
        render json: { success: true, users: @users, meta: pagination_meta(@users) }, status: :ok
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

      def google_oauth2
        puts current_user.inspect
        @user = User.find_for_google_oauth2(params[:uid], params[:access_token], params[:refresh_token], current_user)
        render json: { success: true, user: @user }, status: :ok
      end

      def send_gmail
        current_user.send_gmail(params[:email], params[:subject], params[:body])
        render json: { success: true }, status: :ok
      end

      private

      def password_params
        params.require(:user).permit(:password, :password_confirmation, :current_password)
      end

      def user_profile_params
        params.require(:user).permit(:nickname, :phone, :position, :date_of_birth, :sex)
      end

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end

      def find_for_google_oauth2(uid, access_token, refresh_token)
        user = Identity.where(provider: 'Google', uid:).first&.user
        # user = User.where(:google_token => access_token.credentials.token, :google_uid => access_token.uid ).first
        return user if user

        existing_user = current_user
        return unless existing_user

        existing_user.identities.find_or_create_by(provider: 'Google', uid:,
                                                   meta: { google_token: access_token, google_refresh_token: refresh_token })
        existing_user
      end
    end
  end
end
