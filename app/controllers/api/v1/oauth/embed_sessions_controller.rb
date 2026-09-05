# frozen_string_literal: true

module Api
  module V1
    module Oauth
      class EmbedSessionsController < ApiController
        include Devise::Controllers::Helpers
        include ::Oauth::Sso::EmbedAuthenticatable

        before_action :authenticate_embed_or_general_user!
        before_action :require_embed_session!

        # GET /api/v1/oauth/embed/session
        def show
          response.set_header('Cache-Control', 'no-store')
          render json: {
            success: true,
            data: current_embed_session.as_bootstrap_json.merge(
              assignment: {
                id: current_embed_session.assignment_id,
                code: current_embed_session.essay_assignment&.code,
                category: current_embed_session.essay_assignment&.category,
                title: current_embed_session.essay_assignment&.title
              }
            )
          }, status: :ok
        end
      end
    end
  end
end
