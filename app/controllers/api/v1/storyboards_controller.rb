# frozen_string_literal: true

module Api
  module V1
    class StoryboardsController < ApiController
      def index
        @storyboards = current_user.storyboards.includes(:items).order(created_at: :desc).page(params[:page])
        render json: { success: true, storyboards: @storyboards, meta: pagination_meta(@storyboards) }, status: :ok
      end

      def show
        @storyboard = current_user.storyboards.find(params[:id]).as_json(include: { items: { except: [:sql] } })
        render json: { success: true, storyboard: @storyboard }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Storyboard not found' }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @storyboard = Storyboard.new(storyboard_params)
        @storyboard.user = current_user
        if @storyboard.save
          if params[:item_ids].present?
            items = filter_valid_storyboard_items(params[:item_ids])
            @storyboard.items << items unless items.empty?
          end
          render json: { success: true, storyboard: @storyboard.as_json(include: { items: { except: [:sql] } }) },
                 status: :created
        else
          render json: { success: false, error: @storyboard.errors }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def update
        @storyboard = Storyboard.find(params[:id])
        if @storyboard.update(storyboard_params)
          if params[:item_ids].present?
            @storyboard.items.clear
            items = filter_valid_storyboard_items(params[:item_ids])
            @storyboard.items << items unless items.empty?
          end
          render json: { success: true, storyboard: @storyboard.as_json(include: { items: { except: [:sql] } }) },
                 status: :ok
        else
          render json: { success: false, error: @storyboard.errors }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def destroy
        @storyboard = Storyboard.find(params[:id])
        if @storyboard.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def filter_valid_storyboard_items(item_ids)
        StoryboardItem.where(id: item_ids, is_ready: true, status: StoryboardItem.statuses[:saved])
      end

      def storyboard_params
        params.require(:storyboard).permit(:title, :description)
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
