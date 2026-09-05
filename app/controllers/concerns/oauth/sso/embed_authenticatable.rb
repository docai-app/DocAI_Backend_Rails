# frozen_string_literal: true

module Oauth
  module Sso
    module EmbedAuthenticatable
      extend ActiveSupport::Concern

      included do
        include Devise::Controllers::Helpers
      end

      def current_embed_session
        @current_embed_session
      end

      def embed_session?
        current_embed_session.present?
      end

      def authenticate_embed_or_general_user!
        raw_cookie = EmbedCookie.read(request)
        if raw_cookie.present?
          session = EmbedSessionResolver.resolve(request)
          if session
            @current_embed_session = session
            user = session.general_user
            if user&.active_for_authentication?
              sign_in(:general_user, user, store: false)
              return
            end
          end

          return render_embed_session_error(
            'EMBED_SESSION_EXPIRED',
            'Embed session expired or revoked.',
            :unauthorized
          )
        end

        authenticate_general_user!
      end

      def require_embed_session!
        return if current_embed_session.present?

        render_embed_session_error('EMBED_SESSION_REQUIRED', 'Embed session is required.', :unauthorized)
      end

      def assert_embed_assignment!(assignment)
        return true unless embed_session?
        return true if assignment && current_embed_session.assignment_id.to_s == assignment.id.to_s

        render_embed_session_error(
          'ASSIGNMENT_FORBIDDEN',
          'Embed session cannot access this assignment.',
          :forbidden
        )
        false
      end

      def render_embed_session_error(code, message, status)
        render json: {
          success: false,
          code: code,
          error: message,
          status: Rack::Utils.status_code(status)
        }, status: status
      end
    end
  end
end
