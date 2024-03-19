# frozen_string_literal: true

module Api
  module V1
    class GeneralUserFeedsController < ApiController
      before_action :authenticate_general_user!, only: %i[index show create update destroy]

      def index
        @general_user = current_general_user
        @general_user_feeds = @general_user.general_user_feeds.order(created_at: :desc).includes(:user_marketplace_item).as_json(include: :user_marketplace_item)
        @general_user_feeds = Kaminari.paginate_array(@general_user_feeds).page(params[:page])

        render json: { success: true, general_user_feeds: @general_user_feeds, meta: pagination_meta(@general_user_feeds) },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show
        @general_user = current_general_user
        @general_user_feed = @general_user.general_user_feeds.find_by(id: params[:id])
        render json: { success: true, general_user_feed: @general_user_feed }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @general_user = current_general_user
        @general_user_feed = @general_user.general_user_feeds.create!(general_user_feed_params)
        render json: { success: true, general_user_feed: @general_user_feed }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def update
        @general_user = current_general_user
        @general_user_feed = @general_user.general_user_feeds.find_by(id: params[:id])
        @general_user_feed.update!(general_user_feed_params)
        render json: { success: true, general_user_feed: @general_user_feed }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def destroy
        @general_user = current_general_user
        @general_user_feed = @general_user.general_user_feeds.find_by(id: params[:id])
        @general_user_feed.destroy
        render json: { success: true }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def general_user_feed_params
        params.permit(:title, :description, :cover_image, :file_type, :file_url, :file_size, :user_marketplace_item_id)
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
