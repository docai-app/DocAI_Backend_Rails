# frozen_string_literal: true

require 'json'
require 'net/http'

module AssignmentPackages
  class DifyGenerationClient
    API_URL = ENV.fetch('DIFY_WORKFLOW_API_URL', 'https://aienglish-dify.docai.net/v1/workflows/run')
    TIMEOUT = 300
    MAX_RETRIES = 3

    def initialize(app_key:, user_id:)
      @app_key = app_key
      @user_id = user_id
    end

    def call(inputs:)
      raise ArgumentError, 'Dify app key is missing.' if @app_key.blank?

      payload = request_payload(inputs: inputs, response_mode: 'streaming')
      response_data = execute_workflow_streaming(payload)
      streaming_response = response_from_streaming_events(response_data)
      return streaming_response if streaming_response.present?

      execute_workflow_blocking(request_payload(inputs: inputs, response_mode: 'blocking'))
    end

    private

    def execute_workflow_streaming(payload)
      retries = 0
      response_data = []

      begin
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = payload.to_json

        http.request(request) do |response|
          unless response.code.to_i.between?(200, 299)
            Rails.logger.error(
              "[AssignmentPackages::DifyGenerationClient] Streaming request failed with HTTP #{response.code}: #{response.body.to_s.truncate(500)}"
            )
            return []
          end

          read_sse_response(response, response_data)
        end
      rescue EOFError, RuntimeError => e
        retries += 1
        if retries <= MAX_RETRIES
          Rails.logger.warn(
            "[AssignmentPackages::DifyGenerationClient] Streaming request retry #{retries}/#{MAX_RETRIES}: #{e.message}"
          )
          sleep(2**retries)
          retry
        end

        Rails.logger.error(
          "[AssignmentPackages::DifyGenerationClient] Streaming retries exhausted, falling back to blocking: #{e.message}"
        )
        return []
      rescue Net::ReadTimeout => e
        Rails.logger.error("[AssignmentPackages::DifyGenerationClient] Streaming timeout: #{e.message}")
        return []
      rescue StandardError => e
        Rails.logger.error("[AssignmentPackages::DifyGenerationClient] Streaming request error: #{e.class} #{e.message}")
        return []
      end

      response_data
    end

    def execute_workflow_blocking(payload)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = payload.to_json

      response = http.request(request)
      unless response.code.to_i.between?(200, 299)
        raise "Dify workflow failed with HTTP #{response.code}: #{response.body.to_s.truncate(500)}"
      end

      JSON.parse(response.body)
    end

    def read_sse_response(response, response_data)
      buffer = String.new
      response.read_body do |chunk|
        next if chunk.blank?

        buffer << chunk.dup
        while (index = buffer.index("\n\n"))
          event = buffer.slice!(0, index + 2).strip
          append_sse_event(event, response_data)
        end
      end

      append_sse_event(buffer.strip, response_data) if buffer.strip.present?
    end

    def append_sse_event(event, response_data)
      return unless event.start_with?('data: ')

      json_str = event.sub(/^data: /, '')
      return if json_str.blank?

      response_data << JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.warn(
        "[AssignmentPackages::DifyGenerationClient] Failed to parse streaming chunk: #{e.message}, chunk: #{json_str.to_s.truncate(500)}"
      )
    end

    def response_from_streaming_events(response_data)
      return nil if response_data.blank?

      finished_event = response_data.reverse.find { |event| event['event'] == 'workflow_finished' && event['data'].is_a?(Hash) }
      if finished_event.present?
        data = finished_event['data']
        raise "Dify workflow error: #{data['error']}" if data['error'].present?

        return { 'data' => data }
      end

      text = response_data.filter_map do |event|
        next unless event['event'] == 'text_chunk'

        event.dig('data', 'text') || event['data']
      end.join
      return nil if text.blank?

      { 'data' => { 'outputs' => { 'text' => text } } }
    end

    def request_payload(inputs:, response_mode:)
      {
        inputs: inputs,
        response_mode: response_mode,
        user: @user_id
      }
    end

    def headers
      {
        'Authorization' => "Bearer #{@app_key}",
        'Content-Type' => 'application/json'
      }
    end
  end
end
