# frozen_string_literal: true

module Api
  module V1
    class MarketplaceItemsController < ApiController
      def index
        @marketplace_items = MarketplaceItem.all.order(created_at: :desc)
        @marketplace_items = Kaminari.paginate_array(@marketplace_items).page(params[:page])
        render json: { success: true, marketplace_items: @marketplace_items, meta: pagination_meta(@marketplace_items) },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e }, status: :bad_request
      end

      def show
        @marketplace_item = MarketplaceItem.find(params[:id])
        Apartment::Tenant.switch!(@marketplace_item.entity_name)
        @chatbot_detail = Chatbot.find_by(id: @marketplace_item.chatbot_id)
        render json: { success: true, marketplace_item: @marketplace_item, chatbot_detail: @chatbot_detail },
               status: :ok
      end

      private

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
