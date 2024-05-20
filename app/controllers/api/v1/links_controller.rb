# app/controllers/links_controller.rb
module Api
  module V1
    class LinksController < ApiController
      before_action :set_link, only: [:show, :edit, :update, :destroy]
      before_action :set_link_set

      def index
        @links = @link_set.links
        json_success(links: @links)
      end

      def show
      end

      def new
        @link = @link_set.links.build
      end

      def create
        @link = @link_set.links.build(link_params)
        if @link.save
          # redirect_to [@link_set, @link], notice: 'Link was successfully created.'
          json_success(@link)
        else
          # render :new
          json_fail("failed")
        end
      end

      def edit
      end

      def update
        if @link.update(link_params)
          json_success(link: @link)
        else
          json_fail("failed")
        end
      end

      def destroy
        @link.destroy
        json_success
      end

      private

      def set_link_set
        @link_set = LinkSet.find(params[:link_set_id])
      end

      def set_link
        @link = @link_set.links.find(params[:id])
      end

      def link_params
        params.require(:link).permit(:title, :url, :link_set_id)
      end
    end
  end
end