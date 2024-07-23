# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      before_action :authenticate_general_user!,
                    only: %i[show show_current_user show_purchase_history update delete]

      def show
        @user = current_general_user
        render json: { success: true, user: @user }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_current_user
        @user = current_general_user

        user_data = @user.as_json(include: :energy)
        user_data['role'] = @user.has_role?(:teacher) ? 'teacher' : 'student'

        render json: { success: true, user: user_data }, status: :ok
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
        search_query = @user.user_marketplace_items.ransack(custom_name_cont: params[:custom_name])
        @user_marketplace_items = search_query.result(distinct: true).page(params[:page])
        render json: { success: true, user_marketplace_items: @user_marketplace_items, meta: pagination_meta(@user_marketplace_items) },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_marketplace_item
        @user = current_general_user
        @user_marketplace_item = @user.user_marketplace_items.find_by(id: params[:id])
        Apartment::Tenant.switch!(@user_marketplace_item.marketplace_item.entity_name)
        @chatbot_detail = Chatbot.find_by(id: @user_marketplace_item.marketplace_item.chatbot_id)
        render json: { success: true, user_marketplace_item: @user_marketplace_item, chatbot_detail: @chatbot_detail },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_files
        type = params[:type] || 'image'
        @user = current_general_user
        if type == 'image'
          @files = @user.general_user_files.where(file_type: %w[png jpg]).order(created_at: :desc).page(params[:page])
          render json: { success: true, files: @files, meta: pagination_meta(@files) }, status: :ok
        elsif type == 'document'
          @files = @user.general_user_files.where(file_type: %w[pdf]).order(created_at: :desc).page(params[:page])
          render json: { success: true, files: @files, meta: pagination_meta(@files) }, status: :ok
        end
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

      def update
        @user = current_general_user
        if @user.update(user_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # Write a method to update user his own profile
      def update_profile
        @user = current_general_user
        if @user.update(general_user_profile_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # Write a method to update user his own password
      def update_password
        @user = current_general_user
        if @user.update_with_password({ current_password: params[:current_password], password: params[:password],
                                        password_confirmation: params[:password_confirmation] })
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def destroy_file
        @user = current_general_user
        @user.general_user_files.find_by(id: params[:id]).destroy
        render json: { success: true }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def user_params
        params.permit(:email, :password, :nickname, :phone, :date_of_birth, :sex)
      end

      def general_user_profile_params
        params.permit(:nickname, :phone, :date_of_birth, :sex)
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
    end
  end
end
