# frozen_string_literal: true

require 'base64'
require 'json'
require 'rest-client'
require 'uri'

module EssayOcr
  # Sends already-compressed learner essay images to Kimi without persisting
  # them in Rails or exposing the Moonshot credential to browser clients.
  class MoonshotService
    MAX_IMAGES = 9
    MAX_IMAGE_BYTES = 4 * 1024 * 1024
    MAX_TOTAL_BYTES = 14 * 1024 * 1024
    DEFAULT_BASE_URL = 'https://api.moonshot.cn/v1'
    DEFAULT_MODEL = 'kimi-k2.6'
    ALLOWED_MIME_TYPES = %w[image/jpeg image/png image/webp].freeze
    ESSAY_TRANSCRIPTION_PROMPT =
      'Extract the student’s essay text from the uploaded paper/photo and return a clean transcription in paragraph form, containing only what the student wrote in the essay. Do not correct, edit, or improve anything—keep the student’s original spelling (including misspellings), grammar (even if incorrect), punctuation, and capitalization exactly as written. Remove/ignore all non-essay content such as the school name, headers/footers, titles, prompts, directions, rubrics, names, dates, page numbers, logos, watermarks, teacher comments, doodles, and any unrelated marks or background text visible in the photo. Preserve paragraph breaks only: include line breaks only when the student clearly starts a new paragraph (indentation/blank line/obvious break), and do not reproduce every handwritten line break. If any words are unclear, write your best read and mark unreadable parts as [illegible] or [unclear] without guessing. Output only the essay transcription, nothing else.'.freeze

    class Error < StandardError
      attr_reader :http_status, :error_code, :request_id

      def initialize(message, http_status:, error_code:, request_id: nil)
        super(message)
        @http_status = http_status
        @error_code = error_code
        @request_id = request_id
      end
    end

    attr_reader :model

    def initialize(request_id: nil, requester: nil)
      @request_id = request_id
      @requester = requester || ->(**options) { RestClient::Request.execute(**options) }
      @model = ENV.fetch('MOONSHOT_MODEL', DEFAULT_MODEL).to_s.strip.presence || DEFAULT_MODEL
    end

    def call(images:)
      normalized_images = normalize_images(images)
      response = @requester.call(
        method: :post,
        url: "#{base_url}/chat/completions",
        headers: {
          authorization: "Bearer #{api_key}",
          content_type: :json,
          accept: :json,
          'x-request-id': @request_id
        }.compact,
        payload: JSON.generate(payload(normalized_images)),
        open_timeout: 10,
        timeout: 70
      )
      parse_response(response)
    rescue Error
      raise
    rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout => e
      log_failure('timeout', e)
      raise Error.new(
        'Essay recognition took too long. Please try again.',
        http_status: 504,
        error_code: 'ESSAY_OCR_TIMEOUT',
        request_id: @request_id
      )
    rescue RestClient::ExceptionWithResponse => e
      log_failure('upstream_http', e, upstream_status: e.http_code)
      status = e.http_code.to_i == 429 ? 429 : 502
      code = status == 429 ? 'ESSAY_OCR_BUSY' : 'ESSAY_OCR_UPSTREAM_ERROR'
      message = status == 429 ? 'Essay recognition is busy. Please wait and try again.' :
        'Essay recognition is temporarily unavailable. Please try again.'
      raise Error.new(message, http_status: status, error_code: code, request_id: @request_id)
    rescue JSON::ParserError => e
      log_failure('invalid_json', e)
      raise Error.new(
        'Essay recognition returned an invalid response. Please try again.',
        http_status: 502,
        error_code: 'ESSAY_OCR_INVALID_RESPONSE',
        request_id: @request_id
      )
    rescue StandardError => e
      log_failure('unexpected', e)
      raise Error.new(
        'Essay recognition is temporarily unavailable. Please try again.',
        http_status: 502,
        error_code: 'ESSAY_OCR_UPSTREAM_ERROR',
        request_id: @request_id
      )
    end

    private

    def api_key
      value = ENV['MOONSHOT_API_KEY'].to_s.strip
      return value if value.present?

      raise Error.new(
        'Essay recognition is not configured.',
        http_status: 503,
        error_code: 'ESSAY_OCR_CONFIG_ERROR',
        request_id: @request_id
      )
    end

    def base_url
      value = ENV.fetch('MOONSHOT_BASE_URL', DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, '')
      uri = URI.parse(value)
      return value if uri.is_a?(URI::HTTPS) && uri.host.present?

      raise Error.new(
        'Essay recognition is not configured.',
        http_status: 503,
        error_code: 'ESSAY_OCR_CONFIG_ERROR',
        request_id: @request_id
      )
    rescue URI::InvalidURIError
      raise Error.new(
        'Essay recognition is not configured.',
        http_status: 503,
        error_code: 'ESSAY_OCR_CONFIG_ERROR',
        request_id: @request_id
      )
    end

    def normalize_images(images)
      unless images.is_a?(Array) && images.any?
        raise_validation('Please choose at least one essay image.', 'ESSAY_OCR_IMAGES_REQUIRED')
      end
      if images.length > MAX_IMAGES
        raise_validation("Choose no more than #{MAX_IMAGES} images at once.", 'ESSAY_OCR_TOO_MANY_IMAGES')
      end

      total_bytes = 0
      images.map do |image|
        value = image.respond_to?(:to_unsafe_h) ? image.to_unsafe_h : image.to_h
        data_url = value['dataUrl'] || value[:dataUrl] || value['data_url'] || value[:data_url]
        match = data_url.to_s.match(%r{\Adata:(image/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)\z})
        raise_validation('Only JPEG, PNG, and WebP essay images are supported.', 'ESSAY_OCR_INVALID_IMAGE') unless match

        mime_type = match[1]
        raise_validation('This essay image type is not supported.', 'ESSAY_OCR_INVALID_IMAGE') unless ALLOWED_MIME_TYPES.include?(mime_type)

        binary_size = decoded_size(match[2])
        if binary_size > MAX_IMAGE_BYTES
          raise_validation('One essay image is too large. Please take a clearer, smaller photo.', 'ESSAY_OCR_IMAGE_TOO_LARGE')
        end
        total_bytes += binary_size
        if total_bytes > MAX_TOTAL_BYTES
          raise_validation('The selected essay images are too large. Please upload fewer images.', 'ESSAY_OCR_TOTAL_TOO_LARGE')
        end

        "data:#{mime_type};base64,#{match[2]}"
      end
    end

    def decoded_size(encoded)
      Base64.strict_decode64(encoded).bytesize
    rescue ArgumentError
      raise_validation('One essay image could not be read. Please choose it again.', 'ESSAY_OCR_INVALID_IMAGE')
    end

    def payload(images)
      {
        model: model,
        messages: [
          {
            role: 'system',
            content: 'You are a precise OCR engine for handwritten and printed student essays. Output only the transcribed text.'
          },
          {
            role: 'user',
            content: [
              { type: 'text', text: ESSAY_TRANSCRIPTION_PROMPT },
              *images.map { |data_url| { type: 'image_url', image_url: { url: data_url } } }
            ]
          }
        ],
        thinking: { type: 'disabled' },
        max_completion_tokens: 4096
      }
    end

    def parse_response(response)
      body = JSON.parse(response.body.to_s)
      text = body.dig('choices', 0, 'message', 'content').to_s.strip
      return text if text.present?

      raise Error.new(
        'No essay text was found. Please retake the photo in brighter light.',
        http_status: 422,
        error_code: 'ESSAY_OCR_EMPTY',
        request_id: @request_id
      )
    end

    def raise_validation(message, code)
      raise Error.new(message, http_status: 422, error_code: code, request_id: @request_id)
    end

    def log_failure(phase, exception, upstream_status: nil)
      Rails.logger.error(
        {
          tag: 'essay_ocr_moonshot',
          phase: phase,
          request_id: @request_id,
          upstream_status: upstream_status,
          error_class: exception.class.name,
          error: exception.message.to_s[0, 300]
        }.compact.to_json
      )
    end
  end
end
