# app/controllers/link_sets_controller.rb
module Api
  module V1
    class LinkSetsController < ApiController
      before_action :set_link_set, only: [:show, :edit, :update, :destroy]

      def index
        @link_sets = LinkSet.all
        # json_success(link_sets: @link_sets)
        render json: { success: true, link_sets: @link_sets }, status: :ok
      end

      def show
      end

      def new
        @link_set = LinkSet.new
      end

      def create
        @link_set = LinkSet.new(link_set_params)
        if @link_set.save
          json_success(@link_set)
        else
          json_fail("cannot save")
        end
        
      end

      def edit
      end

      def update
        if @link_set.update(link_set_params)
          json_success(@link_set)
        else
          json_fail("cannot save")
        end
      end

      def destroy
        @link_set.destroy
        # redirect_to link_sets_url, notice: 'Link set was successfully destroyed.'
        json_success
      end

      private

      def set_link_set
        @link_set = LinkSet.find(params[:id])
      end

      def link_set_params
        params.require(:link_set).permit(:name)
      end
    end
  end
end