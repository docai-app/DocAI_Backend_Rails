# frozen_string_literal: true

# app/controllers/link_sets_controller.rb
module Api
  module V1
    class LinkSetsController < ApiNoauthController
      before_action :set_link_set, only: %i[show edit update destroy]
      before_action :set_user_id_and_domain_from_header, only: [:create]

      before_action :get_user_id_and_domain_from_header, except: %i[create update]

      def index
        @link_sets = LinkSet.all
        @link_sets = @link_sets.where(user_id: @user_id) if @user_id.present?

        render json: { success: true, link_sets: @link_sets }, status: :ok
      end

      def show
        # binding.pry
        render json: { success: true, link_set: @link_set.as_json(include: :links) }, status: :ok
      end

      def new
        @link_set = LinkSet.new
      end

      def create
        @link_set = LinkSet.new(link_set_params)
        @link_set.user_id = @user_id
        @link_set.request_origin = @request_origin
        if @link_set.save
          json_success(@link_set)
        else
          json_fail('cannot save')
        end
      end

      def edit; end

      def update
        if @link_set.update(link_set_params)
          json_success(@link_set)
        else
          json_fail('cannot save')
        end
      end

      def destroy
        @link_set.destroy
        # redirect_to link_sets_url, notice: 'Link set was successfully destroyed.'
        json_success
      end

      private

      def set_link_set
        @link_set = LinkSet.includes(:links).find_by!(slug: params[:id])
      end

      def link_set_params
        params.require(:link_set).permit(:name, :description)
      end

      def get_user_id_and_domain_from_header
        @user_id = request.headers['User-Id']
        @request_origin = request.headers['HTTP_ORIGIN'] || request.headers['HTTP_REFERER']
      end

      def set_user_id_and_domain_from_header
        @user_id = request.headers['User-Id']
        @request_origin = request.headers['HTTP_ORIGIN'] || request.headers['HTTP_REFERER']

        render json: { error: 'User-Id header is missing' }, status: :bad_request unless @user_id.present?

        return if @request_origin.present?

        render json: { error: 'Request origin is missing' }, status: :bad_request
      end
    end
  end
end
