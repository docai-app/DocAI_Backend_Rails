# frozen_string_literal: true

# app/controllers/links_controller.rb
module Api
  module V1
    class LinksController < ApiNoauthController
      before_action :set_link_set
      before_action :set_link, only: %i[show edit update destroy]

      def index
        @links = @link_set.links
        json_success(links: @links)
      end

      def show; end

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
          json_fail('failed')
        end
      end

      def edit; end

      def update
        if @link.update(link_params)
          json_success(link: @link)
        else
          json_fail('failed')
        end
      end

      def destroy
        @link.destroy
        json_success
      end

      private

      def set_link_set
        @link_set = LinkSet.find_by!(slug: params[:link_set_id])
      end

      def set_link
        # @link = @link_set.links.where(id: params[:id]).first
        @link = Link.find(params[:id])
      end

      def link_params
        permitted_params = params.require(:link).permit(:title, :url, :link_set_id, meta: {}).to_h
        if params[:link][:meta].is_a?(ActionController::Parameters)
          permitted_params[:meta] =
            params[:link][:meta].permit!
        end
        permitted_params
      end
    end
  end
end
