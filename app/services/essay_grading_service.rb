# frozen_string_literal: true

# app/services/essay_grading_service.rb
require 'net/http'
require 'uri'
require 'json'

class EssayGradingService
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @grading_app_key = essay_grading.grading['app_key']
    @general_context_app_key = essay_grading.general_context['app_key']
    @grading_success = false
    @general_context_success = false
  end

  def run_workflows
    Rails.logger.info("[EssayGradingService] Starting run_workflows for essay grading ID: #{@essay_grading.id}")

    # Run grading workflow with streaming
    Rails.logger.info("[EssayGradingService] Executing grading workflow")
    grading_response = execute_workflow_streaming(@grading_app_key, grading_request_payload)
    Rails.logger.info("[EssayGradingService] Grading workflow response received: #{grading_response.size} chunks")
    @grading_success = process_streaming_response(grading_response, 'grading')
    Rails.logger.info("[EssayGradingService] Grading workflow success: #{@grading_success}")

    # Run general_context workflow (if @general_context_app_key is not nil)
    unless @general_context_app_key.blank?
      Rails.logger.info("[EssayGradingService] Executing general_context workflow")
      general_context_response = execute_workflow_streaming(@general_context_app_key, general_context_request_payload)
      Rails.logger.info("[EssayGradingService] General context workflow response received: #{general_context_response.size} chunks")
      @general_context_success = process_streaming_response(general_context_response, 'general_context')
      Rails.logger.info("[EssayGradingService] General context workflow success: #{@general_context_success}")
    end

    # Final status update
    Rails.logger.info("[EssayGradingService] Updating final status for essay grading ID: #{@essay_grading.id}")
    update_final_status
    Rails.logger.info("[EssayGradingService] Completed run_workflows for essay grading ID: #{@essay_grading.id}")
  end

  private

  def execute_workflow_streaming(app_key, payload)
    response_data = []
    uri = URI.parse(API_URL)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = TIMEOUT
    http.open_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Authorization'] = "Bearer #{app_key}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'text/event-stream'
    request.body = payload.to_json

    Rails.logger.debug("[EssayGradingService] Sending request to #{API_URL} with payload: #{payload.to_json}")

    http.request(request) do |response|
      unless response.code == '200'
        Rails.logger.error("[EssayGradingService] Streaming request failed with code #{response.code}: #{response.body}")
        return []
      end

      response.read_body do |chunk|
        Rails.logger.debug("[EssayGradingService] Received SSE chunk: #{chunk}")
        # Skip non-data lines (SSE protocol lines like "event: ping")
        next unless chunk.start_with?('data: ')

        # Extract JSON data from SSE chunk
        json_str = chunk.sub(/^data: /, '')
        next if json_str.strip.empty?

        begin
          data = JSON.parse(json_str)
          response_data << data
        rescue JSON::ParserError => e
          Rails.logger.error("[EssayGradingService] Failed to parse SSE chunk: #{e.message}, chunk: #{json_str}")
        end
      end
    end

    Rails.logger.debug("[EssayGradingService] Collected #{response_data.size} SSE chunks")
    response_data
  rescue Net::ReadTimeout => e
    Rails.logger.error("[EssayGradingService] Read timeout during streaming: #{e.message}")
    []
  rescue Net::OpenTimeout => e
    Rails.logger.error("[EssayGradingService] Open timeout during streaming: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("[EssayGradingService] Standard error during streaming workflow: #{e.message}")
    Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
    []
  end

  def headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'text/event-stream'
    }
  end

  def grading_request_payload
    inputs = if @essay_grading.essay_assignment.category == 'sentence_builder'
               { sentence_builder: @essay_grading.sentence_builder_for_dify.to_json }
             elsif is_ielts_task_1?
               build_ielts_task_1_inputs('grading')
             else
               { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
             end

    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph] = build_ielts_graph_input('grading')
      Rails.logger.info("[EssayGradingService] Including graph image for grading assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'streaming',
      user: @user_id
    }

    Rails.logger.info("[EssayGradingService] Full grading request payload: #{payload.to_json}")
    payload
  end

  def general_context_request_payload
    inputs = if is_ielts_task_1?
               build_ielts_task_1_inputs('general_context')
             else
               {
                 Essay: @essay_grading.essay,
                 essaytopic: @essay_grading.topic
               }
             end

    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph] = build_ielts_graph_input('general_context')
      Rails.logger.info("[EssayGradingService] Including graph image for general context assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'streaming',
      user: @user_id
    }

    Rails.logger.info("[EssayGradingService] Full general context payload: #{payload.to_json}")
    payload
  end

  def process_streaming_response(response_data, context)
    Rails.logger.info("[EssayGradingService] Processing streaming response for #{context}, received #{response_data.size} chunks")
    return false if response_data.empty?

    begin
      # Collect all workflow_finished events
      workflow_finished_chunks = response_data.select { |chunk| chunk['event'] == 'workflow_finished' && chunk['data'] }

      unless workflow_finished_chunks.any?
        Rails.logger.error("[EssayGradingService] No workflow_finished event found in streaming response: #{response_data}")
        return false
      end

      # Try to merge outputs from all workflow_finished chunks
      outputs = {}
      workflow_finished_chunks.each do |chunk|
        if chunk['data']['error'].present?
          Rails.logger.error("[EssayGradingService] Dify API error in streaming response: #{chunk['data']['error']}")
          return false
        end

        chunk_outputs = chunk['data']['outputs']
        next unless chunk_outputs.is_a?(Hash)

        # Merge outputs (assuming outputs is a hash, potentially with 'text' containing JSON)
        outputs.merge!(chunk_outputs)
      end

      unless outputs.any?
        Rails.logger.error("[EssayGradingService] No valid outputs found in workflow_finished chunks: #{workflow_finished_chunks}")
        return false
      end

      # If outputs['text'] contains a JSON string, parse it
      if outputs['text'].is_a?(String)
        begin
          outputs = JSON.parse(outputs['text'])
        rescue JSON::ParserError => e
          Rails.logger.error("[EssayGradingService] Failed to parse outputs['text'] as JSON: #{e.message}, text: #{outputs['text']}")
          return false
        end
      end

      num_of_suggestions = get_number_of_suggestion(outputs)

      if context == 'grading'
        @essay_grading.update(
          grading: @essay_grading.grading.merge('data' => outputs,
                                               'number_of_suggestion' => num_of_suggestions)
        )
      elsif context == 'general_context'
        @essay_grading.update(
          general_context: @essay_grading.general_context.merge('data' => outputs)
        )
      end

      Rails.logger.info("[EssayGradingService] Successfully processed #{context} response, outputs: #{outputs}")
      true
    rescue StandardError => e
      Rails.logger.error("[EssayGradingService] Error processing streaming response for #{context}: #{e.message}")
      Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      false
    end
  end

  def get_number_of_suggestion(result)
    return 0 unless result.is_a?(Hash) && result['text'].present?

    begin
      json = JSON.parse(result['text'])
      if @essay_grading.category == 'sentence_builder'
        count_sentence_builder_errors(json)
      else
        count_errors(json)
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[EssayGradingService] Failed to parse result text as JSON: #{e.message}")
      Rails.logger.error("[EssayGradingService] Result text: #{result['text']}")
      0
    rescue StandardError => e
      Rails.logger.error("[EssayGradingService] Error counting suggestions: #{e.message}")
      0
    end
  end

  def count_sentence_builder_errors(hash)
    count = 0
    hash['results'].each do |result|
      if result['errors'].is_a?(Array)
        count += result['errors'].count { |error| error['error1'] != 'Correct' }
      end
    end
    count
  end

  def count_errors(hash)
    count = 0
    hash.each do |key, value|
      if key == 'errors' && value.is_a?(Hash)
        count += value.size
      elsif value.is_a?(Hash)
        count += count_errors(value)
      end
    end
    count
  end

  def update_final_status
    if @grading_success && (@general_context_app_key.blank? || @general_context_success)
      @essay_grading.update(status: 'graded')
      @essay_grading.calculate_sentence_builder_score if @essay_grading.category == 'sentence_builder'
      @essay_grading.call_webhook
      Rails.logger.info("[EssayGradingService] Status updated to 'graded' for essay grading ID: #{@essay_grading.id}")
    else
      @essay_grading.update(status: 'stopped')
      Rails.logger.error("[EssayGradingService] Workflow failed, status updated to 'stopped' for essay grading ID: #{@essay_grading.id}")
    end
  end

  def is_ielts_task_1?
    @essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
  end

  def build_ielts_task_1_inputs(workflow_type)
    graph_input = build_ielts_graph_input(workflow_type)

    inputs = if workflow_type == 'general_context'
               {
                 Essay: @essay_grading.essay,
                 essaytopic: @essay_grading.topic,
                 graph: graph_input
               }
             else
               {
                 Essay: @essay_grading.essay,
                 essay_topic: @essay_grading.topic,
                 graph: graph_input
               }
             end

    Rails.logger.info("[EssayGradingService] Building IELTS Task 1 inputs for #{workflow_type} workflow, assignment #{@essay_grading.essay_assignment.id}")
    Rails.logger.info("[EssayGradingService] Graph input: #{graph_input}")
    Rails.logger.info("[EssayGradingService] Essay length: #{inputs[:Essay]&.length}")
    Rails.logger.info("[EssayGradingService] Topic: #{inputs[:essay_topic] || inputs[:essaytopic]}")
    inputs
  end

  def build_ielts_graph_input(workflow_type)
    return nil unless @essay_grading.essay_assignment.graph_image.attached?

    graph_url = @essay_grading.essay_assignment.graph_image.url
    app_key = case workflow_type
              when 'grading'
                @grading_app_key
              when 'general_context'
                @general_context_app_key
              else
                @grading_app_key
              end

    Rails.logger.info("[EssayGradingService] Using app_key for #{workflow_type}: #{app_key&.first(10)}...")

    upload_service = DifyFileUploadService.new(app_key, @user_id)
    upload_result = upload_service.upload_from_url(graph_url, 'image')

    if upload_result.success?
      Rails.logger.info("[EssayGradingService] Successfully uploaded graph to Dify for #{workflow_type}, upload_file_id: #{upload_result.upload_file_id}")
      [{
        'type' => 'image',
        'transfer_method' => 'local_file',
        'upload_file_id' => upload_result.upload_file_id
      }]
    else
      Rails.logger.error("[EssayGradingService] Failed to upload graph to Dify for #{workflow_type}: #{upload_result.error_message}")
      Rails.logger.warn("[EssayGradingService] Falling back to remote URL for graph in #{workflow_type}")
      [{
        'type' => 'image',
        'transfer_method' => 'remote_url',
        'url' => graph_url
      }]
    end
  rescue StandardError => e
    Rails.logger.error("[EssayGradingService] Error building graph input for #{workflow_type}: #{e.message}")
    Rails.logger.warn("[EssayGradingService] Falling back to remote URL for graph in #{workflow_type}")
    [{
      'type' => 'image',
      'transfer_method' => 'remote_url',
      'url' => graph_url
    }]
  end
end