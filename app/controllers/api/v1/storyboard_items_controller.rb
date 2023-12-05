# frozen_string_literal: true

module Api
  module V1
    class StoryboardItemsController < ApiController
      include Authenticatable

      def index
        @storyboard_items = StoryboardItem.where(is_ready: true).where(status: :saved).order(created_at: :desc).page(params[:page])
        render json: { success: true, storyboard_items: @storyboard_items, meta: pagination_meta(@storyboard_items) },
               status: :ok
      end

      def show
        @storyboard_item = StoryboardItem.find(params[:id])
        render json: { success: true, storyboard_item: @storyboard_item }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'StoryboardItem not found' }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def update
        @storyboard_item = StoryboardItem.find(params[:id])
        puts params[:data]
        @storyboard_item.data = params[:data] if @storyboard_item.object_type == 'SmartExtractionSchema_Statistics'
        if @storyboard_item.update(storyboard_item_params)
          render json: { success: true, storyboard_item: @storyboard_item }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @storyboard_item = StoryboardItem.find(params[:id])
        if @storyboard_item.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def storyboard_item_params
        params.permit(:name, :description, :is_ready, :status)
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

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end
    end
  end
end
