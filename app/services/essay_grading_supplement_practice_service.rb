# frozen_string_literal: true

require 'json'
require 'net/http'

class EssayGradingSupplementPracticeService
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)
  MAX_RETRIES = 3 # Maximum retry attempts for errors

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @essay = essay_grading.essay
    @app_key = ENV['essay_grading_supplement_practice_app_key']
  end

  def run_workflow
    task_id = "#{@essay_grading.id}_supplement_practice"
    # Rails.logger.info("[EssayGradingSupplementPracticeService] Starting workflow for essay grading ID: #{@essay_grading.id}, task_id: #{task_id}")

    response_data, _ = execute_workflow_streaming(@app_key, request_payload, task_id)
    success = process_streaming_response(response_data, task_id)

    if success
      Rails.logger.info("[EssayGradingSupplementPracticeService] Successfully processed supplement practice for essay grading ID: #{@essay_grading.id}")
    else
      Rails.logger.error("[EssayGradingSupplementPracticeService] Failed to process supplement practice for essay grading ID: #{@essay_grading.id}")
    end

    success
  end

  private

  def execute_workflow_streaming(app_key, payload, task_id)
    retries = 0
    response_data = []

    begin
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri, headers(app_key))
      request.body = payload.to_json

    #   Rails.logger.debug("[EssayGradingSupplementPracticeService] Sending streaming request to #{API_URL} at #{Time.now.utc}, task_id: #{task_id}")

      http.request(request) do |response|
        if response.code.to_i != 200
          Rails.logger.error("[EssayGradingSupplementPracticeService] Streaming request failed with code #{response.code}: #{response.body}, task_id: #{task_id}")
          return [[], task_id]
        end

        buffer = String.new # Initialize as mutable string
        response.read_body do |chunk|
          next if chunk.empty?

          # Ensure chunk is mutable
          chunk = chunk.dup
          buffer << chunk

          # Split buffer by double newline (SSE events are separated by "\n\n")
          while (index = buffer.index("\n\n"))
            event = buffer.slice!(0, index + 2).strip
            next unless event.start_with?('data: ')

            json_str = event.sub(/^data: /, '')
            next if json_str.empty?

            begin
              data = JSON.parse(json_str)
              response_data << data
            rescue JSON::ParserError => e
              Rails.logger.error("[EssayGradingSupplementPracticeService] Failed to parse SSE chunk: #{e.message}, chunk: #{json_str}, task_id: #{task_id}")
            end
          end
        end

        # Process any remaining data in buffer
        unless buffer.empty? || buffer.strip.empty?
          json_str = buffer.sub(/^data: /, '')
          unless json_str.empty?
            begin
              data = JSON.parse(json_str)
              response_data << data
            rescue JSON::ParserError => e
              Rails.logger.error("[EssayGradingSupplementPracticeService] Failed to parse remaining buffer: #{e.message}, chunk: #{json_str}, task_id: #{task_id}")
            end
          end
        end
      end
    rescue EOFError, RuntimeError => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Error during streaming workflow: #{e.message}, task_id: #{task_id}")
      retries += 1
      if retries <= MAX_RETRIES
        Rails.logger.info("[EssayGradingSupplementPracticeService] Retrying streaming request (attempt #{retries}/#{MAX_RETRIES}), task_id: #{task_id}")
        sleep(2**retries) # Exponential backoff
        retry
      else
        Rails.logger.error("[EssayGradingSupplementPracticeService] Max retries reached for streaming error, attempting blocking request, task_id: #{task_id}")
        return execute_workflow_blocking(app_key, payload, task_id)
      end
    rescue Net::ReadTimeout => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Timeout error during streaming workflow: #{e.message}, task_id: #{task_id}")
      return [[], task_id]
    rescue StandardError => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Standard error during streaming workflow: #{e.message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingSupplementPracticeService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      return [[], task_id]
    end

    # Rails.logger.debug("[EssayGradingSupplementPracticeService] Collected #{response_data.size} SSE chunks, task_id: #{task_id}")
    [response_data, task_id]
  end

  def execute_workflow_blocking(app_key, payload, task_id)
    # Rails.logger.info("[EssayGradingSupplementPracticeService] Falling back to blocking request for task_id: #{task_id}")
    response_data = []

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    # Use blocking mode
    payload = payload.merge(response_mode: 'blocking')
    request = Net::HTTP::Post.new(uri.request_uri, headers(app_key))
    request.body = payload.to_json

    # Rails.logger.debug("[EssayGradingSupplementPracticeService] Sending blocking request to #{API_URL} at #{Time.now.utc}, task_id: #{task_id}")

    begin
      response = http.request(request)
      if response.code.to_i != 200
        Rails.logger.error("[EssayGradingSupplementPracticeService] Blocking request failed with code #{response.code}: #{response.body}, task_id: #{task_id}")
        return [[], task_id]
      end

      body = response.body
    #   Rails.logger.debug("[EssayGradingSupplementPracticeService] Blocking response body: #{body}, task_id: #{task_id}")

      begin
        data = JSON.parse(body)
        if data['error'].present?
          Rails.logger.error("[EssayGradingSupplementPracticeService] Dify API error in blocking response: #{data['error']}, task_id: #{task_id}")
          return [[], task_id]
        end
        response_data << { 'event' => 'workflow_finished', 'data' => data }
      rescue JSON::ParserError => e
        Rails.logger.error("[EssayGradingSupplementPracticeService] Failed to parse blocking response: #{e.message}, body: #{body}, task_id: #{task_id}")
        return [[], task_id]
      end
    rescue Net::ReadTimeout => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Timeout error during blocking workflow: #{e.message}, task_id: #{task_id}")
      return [[], task_id]
    rescue StandardError => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Standard error during blocking workflow: #{e.message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingSupplementPracticeService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      return [[], task_id]
    end

    # Rails.logger.debug("[EssayGradingSupplementPracticeService] Collected #{response_data.size} blocking response chunks, task_id: #{task_id}")
    [response_data, task_id]
  end

  def headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'text/event-stream'
    }
  end

  def request_payload
    {
      inputs: { essay: @essay },
      response_mode: 'streaming',
      user: @user_id
    }
  end

  def process_streaming_response(response_data, task_id)
    # Rails.logger.info("[EssayGradingSupplementPracticeService] Processing streaming response, received #{response_data.size} chunks, task_id: #{task_id}")
    return false if response_data.empty?

    begin
      outputs = nil

      # Try workflow_finished event first
      workflow_finished_chunks = response_data.select { |chunk| chunk['event'] == 'workflow_finished' && chunk['data'] }
      if workflow_finished_chunks.any?
        Rails.logger.info("[EssayGradingSupplementPracticeService] Found #{workflow_finished_chunks.size} workflow_finished chunks for task_id: #{task_id}")
        workflow_finished_chunks.each do |chunk|
          if chunk['data']['error'].present?
            Rails.logger.error("[EssayGradingSupplementPracticeService] Dify API error in streaming response: #{chunk['data']['error']}, task_id: #{task_id}")
            return false
          end

          chunk_outputs = chunk['data']['outputs']
          next unless chunk_outputs.is_a?(Hash) && chunk_outputs['text']

          outputs = chunk_outputs
        end
      end

      # Fallback to text_chunk if no valid workflow_finished outputs
      unless outputs
        text_chunks = response_data.select { |chunk| chunk['event'] == 'text_chunk' && chunk['data'] }
        if text_chunks.any?
          Rails.logger.info("[EssayGradingSupplementPracticeService] Falling back to text_chunk concatenation, found #{text_chunks.size} text chunks for task_id: #{task_id}")
          outputs = text_chunks.map { |chunk| chunk['data'] }.join
        else
          Rails.logger.error("[EssayGradingSupplementPracticeService] No valid outputs found in workflow_finished or text_chunk for task_id: #{task_id}")
          return false
        end
      end

      # Save the supplement practice data
      @essay_grading.grading['supplement_practice'] = outputs
      @essay_grading.save

      Rails.logger.info("[EssayGradingSupplementPracticeService] Successfully processed supplement practice response, task_id: #{task_id}")
      true
    rescue StandardError => e
      Rails.logger.error("[EssayGradingSupplementPracticeService] Error processing streaming response: #{e.message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingSupplementPracticeService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      false
    end
  end
end
