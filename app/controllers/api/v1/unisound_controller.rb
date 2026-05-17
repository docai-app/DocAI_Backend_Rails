# frozen_string_literal: true

module Api
  module V1
    class UnisoundController < ApiController
      # 避免走 ApiController#render_error 的 { success: false, ... } 包装，保持与旧 Next.js API 一致
      rescue_from Exception, with: :render_unisound_exception

      # POST /api/v1/unisound/eval
      # multipart: text, voice (wav), optional durationMs
      def create
        text = params[:text]
        audio_file = params[:voice] || params[:audio]
        duration_ms = params[:durationMs].presence&.to_i || 0

        if text.blank? || audio_file.blank?
          return render json: { 'error' => 'Missing text or audio file' }, status: :bad_request
        end

        unless audio_uploaded_file?(audio_file)
          return render json: {
            'error' => 'Attach the recorded WAV audio (voice or audio) before submitting.'
          }, status: :bad_request
        end

        request_id = request.request_id
        result = Unisound::EvalService.new(request_id: request_id).call(
          text: text,
          audio_file: audio_file,
          duration_ms: duration_ms
        )

        render json: result, status: :ok, headers: response_headers(request_id)
      end

      private

      def render_unisound_exception(exception)
        if exception.is_a?(Unisound::EvalService::Error)
          render json: error_json(exception),
                 status: error_http_status(exception),
                 headers: response_headers(exception.request_id)
          return
        end

        Rails.logger.error(
          {
            tag: 'unisound_eval_rails',
            phase: 'route_uncaught_exception',
            error: exception.message,
            backtrace: exception.backtrace&.first(10)
          }.to_json
        )
        render json: {
          'error' => exception.message,
          'details' => { 'message' => exception.message }
        }, status: :internal_server_error
      end

      def audio_uploaded_file?(audio_file)
        audio_file.respond_to?(:tempfile) || audio_file.is_a?(ActionDispatch::Http::UploadedFile)
      end

      def error_http_status(error)
        case error.http_status
        when 400 then :bad_request
        when 504 then :gateway_timeout
        when 503 then :service_unavailable
        else
          :bad_gateway
        end
      end

      # 与旧 Next.js route 错误体一致：{ error, details?, attemptsUsed? }
      def error_json(error)
        body = { 'error' => error.message }
        return body if error.http_status == 400

        body['details'] = error.payload if error.payload.present?
        body['attemptsUsed'] = error.attempts_used
        body
      end

      def response_headers(request_id)
        { 'x-request-id' => request_id.to_s }
      end
    end
  end
end
