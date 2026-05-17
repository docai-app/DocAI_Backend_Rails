# frozen_string_literal: true

require 'rest-client'
require 'securerandom'

module Unisound
  # 云知声英文口语评测转发（与原 essay-checker api/unisound/eval 行为对齐）
  class EvalService
    ENGLISH_EVAL_URL = ENV.fetch('UNISOUND_EVAL_URL', 'https://edu.hivoice.cn/eval/pcm')
    RETRY_BACKOFF_MS = 350
    RETRYABLE_HTTP_STATUS = [429, 500, 502, 503, 504].freeze
    MAX_RECORDING_SECONDS = 60
    MAX_TEXT_CHARACTERS = 900
    MAX_WORDS = 140
    DEFAULT_APPKEY = 'ms2scwfvhot4bhibhnz5pxs6xpdx3facnf75uxq2@1b6401f8380429fe251071c6561dd288'

    class Error < StandardError
      attr_reader :http_status, :payload, :failure_kind, :attempts_used, :request_id

      def initialize(message, http_status:, failure_kind:, payload: nil, attempts_used: 1, request_id: nil)
        super(message)
        @http_status = http_status
        @payload = payload
        @failure_kind = failure_kind
        @attempts_used = attempts_used
        @request_id = request_id
      end
    end

    def initialize(request_id: nil)
      @request_id = request_id.presence || SecureRandom.uuid
    end

    def call(text:, audio_file:, duration_ms: 0)
      normalized_text = normalize_reference_text(text)
      text_error = validate_reference_text(normalized_text)
      raise Error.new(text_error, http_status: 400, failure_kind: 'validation') if text_error

      duration_error = validate_recording_duration(duration_ms)
      raise Error.new(duration_error, http_status: 400, failure_kind: 'validation') if duration_error

      credentials = credentials!
      mode = select_evaluation_mode(normalized_text)
      word_count = count_english_words(normalized_text)
      timeout_sec = compute_upstream_timeout_sec(word_count, duration_ms)

      raw_data, attempts_used = request_unisound_with_retry(
        text: normalized_text,
        mode: mode,
        audio_file: audio_file,
        credentials: credentials,
        timeout_sec: timeout_sec
      )

      engine_result = raw_data['EngineResult'] || raw_data['result'] || raw_data
      unless engine_result.is_a?(Hash) && engine_result.present?
        log_failure('route_missing_engine_result', payload: raw_data, attempts_used: attempts_used)
        raise Error.new(
          'Invalid response format from Unisound API',
          http_status: 500,
          failure_kind: 'upstream',
          payload: raw_data,
          attempts_used: attempts_used,
          request_id: @request_id
        )
      end

      response_data = ResultFormatter.format(engine_result)
      unless response_data
        log_failure('route_handle_result_null', engine_keys: engine_result.keys, attempts_used: attempts_used)
        raise Error.new(
          'Failed to process result data',
          http_status: 500,
          failure_kind: 'upstream',
          payload: raw_data,
          attempts_used: attempts_used,
          request_id: @request_id
        )
      end

      response_data
    end

    private

    def credentials!
      app_key = ENV['UNISOUND_APP_KEY']&.strip
      app_secret = ENV['UNISOUND_APP_SECRET']&.strip
      if app_key.present? && app_secret.present?
        return "#{app_key}@#{app_secret}"
      end

      appkey = ENV['UNISOUND_APPKEY']&.strip
      return appkey if appkey.present?

      if Rails.env.production?
        raise Error.new(
          'Server configuration is missing UniSound credentials.',
          http_status: 503,
          failure_kind: 'config',
          request_id: @request_id
        )
      end

      DEFAULT_APPKEY
    end

    def score_coefficient
      ENV['UNISOUND_SCORE_COEFFICIENT']&.strip.presence || '1.5'
    end

    def normalize_reference_text(value)
      value.to_s.gsub(/\s+/, ' ').strip
    end

    def validate_reference_text(text)
      return 'Enter the reference text before recording.' if text.blank?
      return "Keep the text under #{MAX_TEXT_CHARACTERS} characters for reliable scoring." if text.length > MAX_TEXT_CHARACTERS

      word_count = count_english_words(text)
      return 'Use English words in the reference text.' if word_count.zero?
      return "Keep the text under #{MAX_WORDS} words for this app's stability guardrail." if word_count > MAX_WORDS

      nil
    end

    def validate_recording_duration(duration_ms)
      return nil unless duration_ms.is_a?(Numeric) && duration_ms.finite? && duration_ms >= 0
      return nil if duration_ms <= MAX_RECORDING_SECONDS * 1_000

      "Recording must be #{MAX_RECORDING_SECONDS} seconds or shorter."
    end

    def count_english_words(text)
      text.scan(/[A-Za-z0-9]+(?:[''-][A-Za-z0-9]+)*/).size
    end

    def select_evaluation_mode(text)
      words = count_english_words(text)
      sentence_count = text.split(/[.!?]+/).map(&:strip).reject(&:blank?).size
      words <= 30 && sentence_count <= 2 ? 'E' : 'C'
    end

    def compute_upstream_timeout_sec(word_count, duration_ms)
      recommended_ms =
        if word_count <= 10
          3_000
        else
          3_000 + (((word_count - 10).to_f / 5).ceil * 1_000)
        end
      audio_aware_ms = duration_ms.positive? ? duration_ms + 35_000 : 58_000
      ms = [recommended_ms + 12_000, audio_aware_ms, 26_000].max
      [ms, 58_000].min / 1000.0
    end

    def request_unisound_with_retry(text:, mode:, audio_file:, credentials:, timeout_sec:)
      attempts = [timeout_sec]
      retry_timeout = [12, timeout_sec * 0.7].max
      if timeout_sec + (RETRY_BACKOFF_MS / 1000.0) + retry_timeout <= 58
        attempts << retry_timeout
      end

      last_error = nil
      attempts_used = 0

      attempts.each_with_index do |per_attempt_timeout, index|
        attempts_used = index + 1
        begin
          path = audio_temp_path(audio_file)
          response = nil
          File.open(path, 'rb') do |voice_io|
            response = RestClient::Request.execute(
              method: :post,
              url: ENGLISH_EVAL_URL,
              payload: {
                text: text,
                mode: mode,
                voice: voice_io
              },
              headers: {
                :'session-id' => SecureRandom.uuid,
                appkey: credentials,
                :'Wrap-Create-Time' => 'true',
                :'score-coefficient' => score_coefficient,
                content_type: :multipart,
                accept: :json,
                multipart: true
              },
              timeout: per_attempt_timeout
            )
          end

          raw_data = parse_json_safely(response.body) || {}
          errcode = extract_error_code(raw_data)
          if errcode.present? && errcode != 0
            log_failure(
              'upstream_engine_errcode',
              attempt: attempts_used,
              errcode: errcode,
              errmsg: extract_error_message(raw_data),
              payload: raw_data
            )
            raise build_upstream_error(
              extract_error_message(raw_data) || "Pronunciation engine rejected the request (code #{errcode}).",
              http_status: 502,
              failure_kind: 'engine_errcode',
              payload: raw_data,
              attempts_used: attempts_used
            )
          end

          return [raw_data, attempts_used]
        rescue RestClient::ExceptionWithResponse => e
          last_error = e
          http_code = e.http_code
          body_data = parse_json_safely(e.response&.body)
          log_failure(
            http_code == 502 ? 'unisound_upstream_http_502' : 'upstream_http_not_ok',
            attempt: attempts_used,
            upstream_http_status: http_code,
            errmsg: extract_error_message(body_data),
            errcode: extract_error_code(body_data),
            payload: body_data || e.response&.body,
            will_retry: index < attempts.length - 1 && RETRYABLE_HTTP_STATUS.include?(http_code)
          )

          if index < attempts.length - 1 && RETRYABLE_HTTP_STATUS.include?(http_code)
            sleep(RETRY_BACKOFF_MS / 1000.0)
            next
          end

          raise build_upstream_error(
            extract_error_message(body_data) || "Pronunciation service is temporarily unavailable (HTTP #{http_code}).",
            http_status: http_code == 504 ? 504 : 502,
            failure_kind: 'upstream_http',
            payload: body_data,
            attempts_used: attempts_used
          )
        rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout => e
          last_error = e
          log_failure('upstream_abort_timeout', attempt: attempts_used, error: e.message)
          if index < attempts.length - 1
            sleep(RETRY_BACKOFF_MS / 1000.0)
            next
          end

          raise build_upstream_error(
            'The scoring request timed out. Try a shorter sentence or a shorter recording.',
            http_status: 504,
            failure_kind: 'timeout',
            attempts_used: attempts_used
          )
        rescue SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError => e
          last_error = e
          log_failure('unisound_network_fetch_failed', attempt: attempts_used, error: e.class.name, message: e.message)
          if index < attempts.length - 1
            sleep(RETRY_BACKOFF_MS / 1000.0)
            next
          end

          raise build_upstream_error(
            'Could not connect to the pronunciation service. Please try again in a few seconds.',
            http_status: 502,
            failure_kind: 'network',
            attempts_used: attempts_used
          )
        rescue StandardError => e
          last_error = e
          log_failure('upstream_fetch_exception', attempt: attempts_used, error: e.class.name, message: e.message)
          if index < attempts.length - 1
            sleep(RETRY_BACKOFF_MS / 1000.0)
            next
          end

          raise build_upstream_error(
            'Could not connect to the pronunciation service. Please try again in a few seconds.',
            http_status: 502,
            failure_kind: 'network',
            attempts_used: attempts_used
          )
        end
      end

      raise build_upstream_error(
        last_error&.message || 'Pronunciation scoring failed.',
        http_status: 502,
        failure_kind: 'unknown',
        attempts_used: attempts_used
      )
    end

    def audio_temp_path(audio_file)
      if audio_file.respond_to?(:tempfile) && audio_file.tempfile
        audio_file.tempfile.path
      elsif audio_file.is_a?(String)
        audio_file
      else
        raise Error.new(
          'Attach the recorded WAV audio (voice or audio) before submitting.',
          http_status: 400,
          failure_kind: 'validation',
          request_id: @request_id
        )
      end
    end

    def parse_json_safely(body)
      return nil if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def extract_error_code(payload)
      return nil unless payload.is_a?(Hash)

      value = payload['errcode'] || payload['errorcode'] || payload['ErrCode'] || payload['ErrorCode']
      value.is_a?(Numeric) ? value.to_i : nil
    end

    def extract_error_message(payload)
      return nil unless payload.is_a?(Hash)

      value = payload['errmsg'] || payload['errorMessage'] || payload['ErrMsg'] || payload['ErrorMessage']
      value.is_a?(String) ? value : nil
    end

    def build_upstream_error(message, http_status:, failure_kind:, payload: nil, attempts_used: 1)
      Error.new(
        message,
        http_status: http_status,
        failure_kind: failure_kind,
        payload: payload,
        attempts_used: attempts_used,
        request_id: @request_id
      )
    end

    def log_failure(phase, **fields)
      Rails.logger.error(
        {
          tag: 'unisound_eval_rails',
          requestId: @request_id,
          phase: phase,
          time: Time.current.iso8601,
          upstreamUrl: ENGLISH_EVAL_URL,
          **fields
        }.to_json
      )
    end
  end
end
