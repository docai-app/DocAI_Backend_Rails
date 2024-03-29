# frozen_string_literal: true

module Api
  module V1
    class AgentToolsController < ApiController
      include Authenticatable

      before_action :authenticate, only: %i[show create update destroy mark_messages_read]

      def index
        @ats = AgentTool.all.order(created_at: :desc)
        @ats = @ats.where(category: params[:category]) if params[:category].present?
        @ats = Kaminari.paginate_array(@ats).page(params[:page])

        render json: { success: true, agent_tools: @ats, meta: pagination_meta(@ats) }, status: :ok
      end

      def show; end

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
