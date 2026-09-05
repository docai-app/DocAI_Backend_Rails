# frozen_string_literal: true

module Oauth
  module Sso
    class LaunchesController < ApplicationController
      before_action :switch_public_tenant_for_sso

      # POST /oauth/sso/launch
      def create
        request_id = require_request_id!
        application = ClientAuthenticator.authenticate!(request)
        input = parse_body!
        assert_idempotency_key!(input[:nonce])

        result = LaunchIssuer.new(
          application: application,
          input: input,
          request_id: request_id
        ).call

        response.set_header('Cache-Control', 'no-store')
        response.set_header('Pragma', 'no-cache')
        response.set_header('X-Request-Id', request_id)
        render json: { data: result }, status: :created
      rescue ::Oauth::Sso::Error => e
        render_sso_error(e, request_id: request.headers['X-Request-Id'])
      end

      private

      def switch_public_tenant_for_sso
        Apartment::Tenant.switch!('public') if defined?(Apartment)
      rescue StandardError => e
        Rails.logger.warn("[Oauth::Sso::Launch] tenant switch failed: #{e.class}")
      end

      def require_request_id!
        request_id = request.headers['X-Request-Id'].to_s.strip
        if request_id.blank?
          raise ::Oauth::Sso::Error.new('INVALID_REQUEST', 'X-Request-Id is required.', http_status: 400)
        end

        request_id
      end

      def assert_idempotency_key!(nonce)
        key = request.headers['Idempotency-Key'].to_s.strip
        if key.blank?
          raise ::Oauth::Sso::Error.new('INVALID_REQUEST', 'Idempotency-Key is required.', http_status: 400)
        end
        return if key == nonce.to_s

        raise ::Oauth::Sso::Error.new('INVALID_REQUEST', 'Idempotency-Key must match nonce.', http_status: 400)
      end

      def parse_body!
        {
          subject: params[:subject],
          assignment_id: params[:assignmentId] || params[:assignment_id],
          mode: params[:mode],
          return_origin: params[:returnOrigin] || params[:return_origin],
          provider_origin: params[:providerOrigin] || params[:provider_origin],
          nonce: params[:nonce]
        }
      end

      def render_sso_error(error, request_id: nil)
        response.set_header('Cache-Control', 'no-store')
        response.set_header('X-Request-Id', request_id) if request_id.present?
        render json: {
          error: {
            code: error.code,
            message: error.message,
            requestId: request_id
          }
        }, status: error.http_status
      end
    end
  end
end
