# frozen_string_literal: true

module Api
  module V1
    class EssayOcrController < ApiController
      MAX_REQUEST_BYTES = 20 * 1024 * 1024

      rescue_from StandardError, with: :render_essay_ocr_exception
      before_action :authenticate_general_user!
      before_action :authorize_essay_ocr!
      before_action :validate_request_size!
      before_action :enforce_rate_limit!

      # POST /api/v1/essay_ocr
      # JSON: { images: [{ name, type, dataUrl }] }
      def create
        service = EssayOcr::MoonshotService.new(request_id: request.request_id)
        text = service.call(images: params[:images])
        render json: {
          success: true,
          provider: 'kimi',
          model: service.model,
          text: text,
          request_id: request.request_id
        }, status: :ok, headers: response_headers
      end

      private

      def authorize_essay_ocr!
        return if current_general_user.aienglish_features_list.map(&:to_s).include?('essay')

        render json: {
          success: false,
          error: 'You do not have access to Essay OCR.',
          error_code: 'ESSAY_OCR_FORBIDDEN',
          request_id: request.request_id
        }, status: :forbidden, headers: response_headers
      end

      def validate_request_size!
        return unless request.content_length.to_i > MAX_REQUEST_BYTES

        raise EssayOcr::MoonshotService::Error.new(
          'The selected essay images are too large. Please upload fewer images.',
          http_status: 413,
          error_code: 'ESSAY_OCR_REQUEST_TOO_LARGE',
          request_id: request.request_id
        )
      end

      def enforce_rate_limit!
        EssayOcr::RateLimiter.new(request_id: request.request_id).check!(
          user_id: current_general_user.id,
          ip: request.remote_ip
        )
      end

      def render_essay_ocr_exception(exception)
        if exception.is_a?(EssayOcr::MoonshotService::Error)
          render json: {
            success: false,
            error: exception.message,
            error_code: exception.error_code,
            request_id: exception.request_id || request.request_id
          }, status: exception.http_status, headers: response_headers
          return
        end

        Rails.logger.error(
          {
            tag: 'essay_ocr_controller',
            request_id: request.request_id,
            error_class: exception.class.name,
            error: exception.message.to_s[0, 300]
          }.to_json
        )
        render json: {
          success: false,
          error: 'Essay recognition is temporarily unavailable. Please try again.',
          error_code: 'ESSAY_OCR_INTERNAL_ERROR',
          request_id: request.request_id
        }, status: :internal_server_error, headers: response_headers
      end

      def response_headers
        { 'x-request-id' => request.request_id.to_s }
      end
    end
  end
end
