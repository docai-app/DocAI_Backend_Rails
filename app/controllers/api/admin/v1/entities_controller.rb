# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EntitiesController < AdminApiController
        include AdminAuthenticator

        def index
          @entities = Entity.all
          render json: { success: true, entities: @entities }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end
      end
    end
  end
end
