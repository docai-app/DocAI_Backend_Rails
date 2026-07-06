# frozen_string_literal: true

# app/services/essay_grading_service.rb
require 'rest-client'
require 'json'
require 'net/http'

class EssayGradingService
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  COMPLETION_API_URL = 'https://aienglish-dify.docai.net/v1/completion-messages'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)
  MAX_RETRIES = 3 # Maximum retry attempts for errors

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @grading_app_key = essay_grading.grading['app_key']
    @general_context_app_key = essay_grading.general_context['app_key']
    @revised_essay_app_key = essay_grading.revised_essay_app_key
    @grading_success = false
    @general_context_success = false
    @revised_essay_success = false
    @speaking_scoring_success = !speaking_essay?
  end

  def run_workflows
    @essay_grading.clear_grading_errors!

    # Run grading workflow with streaming
    grading_task_id = "#{@essay_grading.id}_grading"
    # Rails.logger.info("[EssayGradingService] Executing grading workflow with task_id: #{grading_task_id}")
    grading_response, _ = execute_workflow_streaming(@grading_app_key, grading_request_payload, grading_task_id)
    # Rails.logger.info("[EssayGradingService] Grading workflow response received: #{grading_response.size} chunks, task_id: #{grading_task_id}")
    @grading_success = process_streaming_response(grading_response, grading_task_id, 'grading')
    Rails.logger.info("[EssayGradingService] Grading workflow success: #{@grading_success}")
    record_workflow_error('grading', 'Grading workflow returned no valid outputs.', task_id: grading_task_id) unless @grading_success

    # Run general_context workflow (if @general_context_app_key is not nil)
    unless @general_context_app_key.blank?
      general_context_task_id = "#{@essay_grading.id}_general_context"
      # Rails.logger.info("[EssayGradingService] Executing general_context workflow with task_id: #{general_context_task_id}")
      general_context_response, _ = execute_workflow_streaming(@general_context_app_key, general_context_request_payload, general_context_task_id)
      # Rails.logger.info("[EssayGradingService] General context workflow response received: #{general_context_response.size} chunks, task_id: #{general_context_task_id}")
      @general_context_success = process_streaming_response(general_context_response, general_context_task_id, 'general_context')
      Rails.logger.info("[EssayGradingService] General context workflow success: #{@general_context_success}")
      unless @general_context_success
        record_workflow_error(
          'general_context',
          'General context workflow returned no valid outputs.',
          task_id: general_context_task_id
        )
      end
    end

    unless @revised_essay_app_key.blank?
      revised_essay_response = execute_completion(@revised_essay_app_key, revised_essay_completion_payload)
      @revised_essay_success = process_completion_response(revised_essay_response)
      Rails.logger.info("[EssayGradingService] Revised essay workflow success: #{@revised_essay_success}")
      record_workflow_error('revised_essay', 'Revised essay workflow failed.') unless @revised_essay_success
    end

    if speaking_essay? && core_workflows_successful?
      @speaking_scoring_success = SpeakingEssay::ScoringService.new(@essay_grading.reload).call
      Rails.logger.info("[EssayGradingService] Speaking essay scoring workflow success: #{@speaking_scoring_success}")
      record_workflow_error('speaking_scoring', 'Speaking essay scoring workflow failed.') unless @speaking_scoring_success
    end

    # Final status update
    # Rails.logger.info("[EssayGradingService] Updating final status for essay grading ID: #{@essay_grading.id}")
    update_final_status
    # Rails.logger.info("[EssayGradingService] Completed run_workflows for essay grading ID: #{@essay_grading.id}")
  rescue StandardError => e
    message = "Unexpected error during essay grading workflows: #{e.message}"
    Rails.logger.error("[EssayGradingService] #{message}")
    Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
    record_workflow_error('run_workflows', message, error_class: e.class.name)
    @essay_grading.record_grading_failure_summary!(failed_steps: ['run_workflows'], message: e.message)
    @essay_grading.update(status: 'stopped') if @essay_grading.pending?
    raise
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

      # Rails.logger.debug("[EssayGradingService] Sending streaming request to #{API_URL} at #{Time.now.utc}, task_id: #{task_id}")

      http.request(request) do |response|
        if response.code.to_i != 200
          message = "Streaming request failed with code #{response.code}"
          Rails.logger.error("[EssayGradingService] #{message}: #{response.body}, task_id: #{task_id}")
          record_workflow_error(
            workflow_stage_from_task_id(task_id),
            message,
            task_id: task_id,
            response_body: response.body.to_s.truncate(500)
          )
          return [[], task_id]
        end

        # Rails.logger.debug("[EssayGradingService] Response headers: #{response.to_hash.inspect}, task_id: #{task_id}")

        buffer = String.new # Initialize as mutable string
        response.read_body do |chunk|
          # Rails.logger.debug("[EssayGradingService] Received raw chunk: #{chunk.inspect}, task_id: #{task_id}")
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

            # Rails.logger.debug("[EssayGradingService] Processed SSE chunk: #{json_str}, task_id: #{task_id}")

            begin
              data = JSON.parse(json_str)
              response_data << data
            rescue JSON::ParserError => e
              Rails.logger.error("[EssayGradingService] Failed to parse SSE chunk: #{e.message}, chunk: #{json_str}, task_id: #{task_id}")
            end
          end
        end

        # Process any remaining data in buffer
        unless buffer.empty? || buffer.strip.empty?
          json_str = buffer.sub(/^data: /, '')
          # Rails.logger.debug("[EssayGradingService] Processing remaining buffer: #{json_str}, task_id: #{task_id}")
          unless json_str.empty?
            begin
              data = JSON.parse(json_str)
              response_data << data
            rescue JSON::ParserError => e
              Rails.logger.error("[EssayGradingService] Failed to parse remaining buffer: #{e.message}, chunk: #{json_str}, task_id: #{task_id}")
            end
          end
        end
      end
    rescue EOFError, RuntimeError => e
      Rails.logger.error("[EssayGradingService] Error during streaming workflow: #{e.message}, task_id: #{task_id}")
      retries += 1
      if retries <= MAX_RETRIES
        # Rails.logger.info("[EssayGradingService] Retrying streaming request (attempt #{retries}/#{MAX_RETRIES}), task_id: #{task_id}")
        sleep(2**retries) # Exponential backoff
        retry
      else
        Rails.logger.error("[EssayGradingService] Max retries reached for streaming error, attempting blocking request, task_id: #{task_id}")
        return execute_workflow_blocking(app_key, payload, task_id)
      end
    rescue Net::ReadTimeout => e
      message = "Timeout error during streaming workflow: #{e.message}"
      Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
      record_workflow_error(workflow_stage_from_task_id(task_id), message, task_id: task_id)
      return [[], task_id]
    rescue StandardError => e
      message = "Standard error during streaming workflow: #{e.message}"
      Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      record_workflow_error(
        workflow_stage_from_task_id(task_id),
        message,
        task_id: task_id,
        error_class: e.class.name
      )
      return [[], task_id]
    end

    # Rails.logger.debug("[EssayGradingService] Collected #{response_data.size} SSE chunks, task_id: #{task_id}")
    [response_data, task_id]
  end

  def execute_workflow_blocking(app_key, payload, task_id)
    Rails.logger.info("[EssayGradingService] Falling back to blocking request for task_id: #{task_id}")
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

    Rails.logger.debug("[EssayGradingService] Sending blocking request to #{API_URL} at #{Time.now.utc}, task_id: #{task_id}")

    begin
      response = http.request(request)
      if response.code.to_i != 200
        message = "Blocking request failed with code #{response.code}"
        Rails.logger.error("[EssayGradingService] #{message}: #{response.body}, task_id: #{task_id}")
        record_workflow_error(
          workflow_stage_from_task_id(task_id),
          message,
          task_id: task_id,
          response_body: response.body.to_s.truncate(500)
        )
        return [[], task_id]
      end

      Rails.logger.debug("[EssayGradingService] Blocking response headers: #{response.to_hash.inspect}, task_id: #{task_id}")
      body = response.body
      Rails.logger.debug("[EssayGradingService] Blocking response body: #{body}, task_id: #{task_id}")

      begin
        data = JSON.parse(body)
        if data['error'].present?
          message = "Dify API error in blocking response: #{data['error']}"
          Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
          record_workflow_error(workflow_stage_from_task_id(task_id), message, task_id: task_id)
          return [[], task_id]
        end
        response_data << { 'event' => 'workflow_finished', 'data' => data }
      rescue JSON::ParserError => e
        message = "Failed to parse blocking response: #{e.message}"
        Rails.logger.error("[EssayGradingService] #{message}, body: #{body}, task_id: #{task_id}")
        record_workflow_error(workflow_stage_from_task_id(task_id), message, task_id: task_id)
        return [[], task_id]
      end
    rescue Net::ReadTimeout => e
      message = "Timeout error during blocking workflow: #{e.message}"
      Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
      record_workflow_error(workflow_stage_from_task_id(task_id), message, task_id: task_id)
      return [[], task_id]
    rescue StandardError => e
      message = "Standard error during blocking workflow: #{e.message}"
      Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      record_workflow_error(
        workflow_stage_from_task_id(task_id),
        message,
        task_id: task_id,
        error_class: e.class.name
      )
      return [[], task_id]
    end

    Rails.logger.debug("[EssayGradingService] Collected #{response_data.size} blocking response chunks, task_id: #{task_id}")
    [response_data, task_id]
  end

  def headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'text/event-stream'
    }
  end

  def completion_headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json'
    }
  end

  def grading_request_payload
    inputs = if @essay_grading.essay_assignment.category == 'sentence_builder'
               { sentence_builder: @essay_grading.sentence_builder_for_dify.to_json }
             elsif talk_lab_speaking?
               talk_lab_speaking_inputs
             elsif is_ielts_task_1?
               build_ielts_task_1_inputs('grading')
             else
               { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
             end

    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph] = build_ielts_graph_input('grading')
      # Rails.logger.info("[EssayGradingService] Including graph image for grading assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'streaming',
      user: @user_id
    }

    # Rails.logger.info("[EssayGradingService] Full grading request payload: #{payload.to_json}")
    payload
  end

  def general_context_request_payload
    inputs = if talk_lab_speaking?
               talk_lab_speaking_inputs
             elsif is_ielts_task_1?
               build_ielts_task_1_inputs('general_context')
             else
               {
                 Essay: @essay_grading.essay,
                 essaytopic: @essay_grading.topic
               }
             end

    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph] = build_ielts_graph_input('general_context')
      # Rails.logger.info("[EssayGradingService] Including graph image for general context assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'streaming',
      user: @user_id
    }

    Rails.logger.info("[EssayGradingService] Full general context payload: #{payload.to_json}")
    payload
  end

  def revised_essay_completion_payload
    {
      inputs: {
        essay: @essay_grading.essay,
        topic: @essay_grading.topic,
        essay_type: @essay_grading.essay_assignment.revised_essay_type_label_with_number,
        guide: @essay_grading.essay_assignment.revised_essay_type_label
      },
      response_mode: 'blocking',
      user: @user_id
    }
  end

  def process_streaming_response(response_data, task_id, context)
    # Rails.logger.info("[EssayGradingService] Processing streaming response for #{context}, received #{response_data.size} chunks, task_id: #{task_id}")
    if response_data.empty?
      record_workflow_error(context, 'Workflow response was empty.', task_id: task_id)
      return false
    end

    begin
      outputs = nil

      # Try workflow_finished event first
      workflow_finished_chunks = response_data.select { |chunk| chunk['event'] == 'workflow_finished' && chunk['data'] }
      if workflow_finished_chunks.any?
        # Rails.logger.info("[EssayGradingService] Found #{workflow_finished_chunks.size} workflow_finished chunks for task_id: #{task_id}")
        workflow_finished_chunks.each do |chunk|
          if chunk['data']['error'].present?
            message = "Dify API error in streaming response: #{chunk['data']['error']}"
            Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
            record_workflow_error(context, message, task_id: task_id)
            return false
          end

          chunk_outputs = chunk['data']['outputs']
          next unless chunk_outputs.is_a?(Hash) && chunk_outputs['text']

          # outputs = chunk_outputs['text']
          outputs = chunk_outputs
          # If outputs['text'] is a JSON string, parse it
          # begin
          #   outputs = JSON.parse(json_str)
          #   break # Use the first valid outputs
          # rescue JSON::ParserError => e
          #   Rails.logger.error("[EssayGradingService] Failed to parse workflow_finished outputs['text'] as JSON: #{e.message}, text: #{chunk_outputs['text']}, task_id: #{task_id}")
          # end
        end
      end

      # Fallback to text_chunk if no valid workflow_finished outputs
      unless outputs
        text_chunks = response_data.select { |chunk| chunk['event'] == 'text_chunk' && chunk['data']  }
        if text_chunks.any?
          # Rails.logger.info("[EssayGradingService] Falling back to text_chunk concatenation, found #{text_chunks.size} text chunks for task_id: #{task_id}")
          outputs = text_chunks.map { |chunk| chunk['data'] }.join
          # begin
          #   # Try parsing the raw concatenated string
          #   outputs = JSON.parse(json_str)
          # rescue JSON::ParserError => e
          #   Rails.logger.warn("[EssayGradingService] Failed to parse concatenated text_chunks as JSON: #{e.message}, attempting to fix JSON, task_id: #{task_id}")
          #   # Attempt to fix the JSON string
          #   fixed_json_str = fix_json_string(json_str)
          #   begin
          #     outputs = JSON.parse(fixed_json_str)
          #   rescue JSON::ParserError => e
          #     Rails.logger.error("[EssayGradingService] Failed to parse fixed text_chunks as JSON: #{e.message}, fixed text: #{fixed_json_str}, task_id: #{task_id}")
          #     # return false
          #   end
          # end
        else
          message = 'No valid outputs found in workflow_finished or text_chunk'
          Rails.logger.error("[EssayGradingService] #{message} for task_id: #{task_id}")
          record_workflow_error(context, message, task_id: task_id)
          return false
        end
      end

      # unless outputs.is_a?(Hash)
      #   Rails.logger.error("[EssayGradingService] Outputs is not a hash: #{outputs}, task_id: #{task_id}")
      #   return false
      # end

      if context == 'grading'
        num_of_suggestions = get_number_of_suggestion(outputs)
        @essay_grading.update(
          grading: @essay_grading.grading.merge('data' => outputs,
                                               'number_of_suggestion' => num_of_suggestions)
        )
      elsif context == 'general_context'
        @essay_grading.update(
          general_context: @essay_grading.general_context.merge('data' => outputs)
        )
      end

      # Rails.logger.info("[EssayGradingService] Successfully processed #{context} response, outputs: #{outputs}, task_id: #{task_id}")
      true
    rescue StandardError => e
      message = "Error processing streaming response for #{context}: #{e.message}"
      Rails.logger.error("[EssayGradingService] #{message}, task_id: #{task_id}")
      Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      record_workflow_error(context, message, task_id: task_id, error_class: e.class.name)
      false
    end
  end

  def execute_completion(app_key, payload)
    RestClient::Request.execute(
      method: :post,
      url: COMPLETION_API_URL,
      payload: payload.to_json,
      headers: completion_headers(app_key),
      timeout: TIMEOUT,
      open_timeout: 100
    )
  rescue RestClient::ExceptionWithResponse => e
    message = "Completion API request failed with code #{e.response&.code}"
    Rails.logger.error("[EssayGradingService] Exception when calling completion API: #{e.response}")
    record_workflow_error(
      'revised_essay',
      message,
      error_class: e.class.name,
      response_body: e.response&.body.to_s.truncate(500)
    )
    nil
  rescue StandardError => e
    message = "Standard error when calling completion API: #{e.message}"
    Rails.logger.error("[EssayGradingService] #{message}")
    record_workflow_error('revised_essay', message, error_class: e.class.name)
    nil
  end

  def process_completion_response(response)
    unless response && response.code == 200
      record_workflow_error('revised_essay', 'Revised essay completion API returned an invalid response.')
      return false
    end

    result = JSON.parse(response.body)
    revised_outputs =
      if result.dig('data', 'outputs').present?
        result['data']['outputs']
      elsif result['answer'].present?
        { 'text' => result['answer'] }
      end

    if revised_outputs.blank?
      record_workflow_error('revised_essay', 'Revised essay workflow returned no outputs.')
      return false
    end

    @essay_grading.update(
      revised_essay: @essay_grading.revised_essay.merge('data' => revised_outputs)
    )
    true
  rescue StandardError => e
    message = "Error processing revised essay response: #{e.message}"
    Rails.logger.error("[EssayGradingService] #{message}")
    record_workflow_error('revised_essay', message, error_class: e.class.name)
    false
  end

  # Method to fix common JSON syntax errors
  def fix_json_string(json_str)
    # Step 1: Remove trailing commas
    json_str = json_str.gsub(/,\s*}/, '}').gsub(/,\s*]/, ']')

    # Step 2: Add missing quotes around keys
    json_str = json_str.gsub(/([{,]\s*)(\w+)(:)/) { |match| "#{$1}\"#{$2}\"#{$3}" }

    # Step 3: Fix unclosed objects and arrays
    open_braces = json_str.scan(/{/).count
    close_braces = json_str.scan(/}/).count
    open_brackets = json_str.scan(/\[/).count
    close_brackets = json_str.scan(/\]/).count

    json_str += '}' * (open_braces - close_braces) if open_braces > close_braces
    json_str += ']' * (open_brackets - close_brackets) if open_brackets > close_brackets

    # Step 4: Fix missing quotes around values that should be strings
    json_str = json_str.gsub(/(:)\s*([^,\]\}\s]+)([,\]\}])/) do |match|
      if $2.match?(/^\d+$/) || $2.match?(/^(true|false|null)$/)
        "#{$1} #{$2}#{$3}"
      else
        "#{$1} \"#{$2}\"#{$3}"
      end
    end

    # Step 5: Replace malformed key-value pairs (e.g., "corrshould need -> should provide")
    json_str = json_str.gsub(/("\w+":\s*)(\w+\s*->\s*[^\,\]\}]+)/) do |match|
      key, value = $1, $2
      corrected_value = value.split('->').last.strip
      "#{key}\"#{corrected_value}\""
    end

    # Step 6: Fix incomplete objects (e.g., "errors": })
    json_str = json_str.gsub(/"errors":\s*}/, '"errors": {}')

    # Step 7: Ensure the entire JSON is wrapped in braces
    json_str = "{#{json_str}}" unless json_str.start_with?('{')

    Rails.logger.debug("[EssayGradingService] Fixed JSON string: #{json_str}")
    json_str
  end

  def get_number_of_suggestion(result)
    # Rails.logger.debug("[EssayGradingService] result: #{result}")
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
      Rails.logger.error("[EssayGradingService] Result text: #{result}")
      0
    # begin
    #   if @essay_grading.category == 'sentence_builder'
    #     count_sentence_builder_errors(result)
    #   else
    #     count_errors(result)
    #   end
    rescue StandardError => e
      Rails.logger.error("[EssayGradingService] Error counting suggestions: #{e.message}")
      0
    end
  end

  def count_sentence_builder_errors(hash)
    count = 0
    hash['results']&.each do |result|
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
    if @grading_success &&
       (@general_context_app_key.blank? || @general_context_success) &&
       (@revised_essay_app_key.blank? || @revised_essay_success) &&
       @speaking_scoring_success
      @essay_grading.update(status: 'graded')
      @essay_grading.calculate_sentence_builder_score if @essay_grading.category == 'sentence_builder'
      @essay_grading.call_webhook
      Rails.logger.info("[EssayGradingService] Status updated to 'graded' for essay grading ID: #{@essay_grading.id}")
    else
      failed_steps = workflow_failed_steps
      @essay_grading.record_grading_failure_summary!(failed_steps:)
      @essay_grading.update(status: 'stopped')
      Rails.logger.error("[EssayGradingService] Workflow failed, status updated to 'stopped' for essay grading ID: #{@essay_grading.id}")
      # 发送通知邮件给管理员
      begin
        AdminNotificationMailer.assignment_stopped_notification(@essay_grading).deliver_later
      rescue StandardError => e
        Rails.logger.error("[EssayGradingService] Failed to send admin notification email: #{e.message}")
      end
    end
  end

  def is_ielts_task_1?
    @essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
  end

  def speaking_essay?
    @essay_grading.category == 'speaking_essay'
  end

  def talk_lab_speaking?
    @essay_grading.category == 'talk_lab_speaking'
  end

  def talk_lab_speaking_inputs
    payload = @essay_grading.meta.is_a?(Hash) ? @essay_grading.meta['talk_lab_speaking'] : {}
    payload = payload.is_a?(Hash) ? payload : {}

    {
      Essay: @essay_grading.essay,
      essaytopic: @essay_grading.topic,
      transcript: payload['transcript'].presence || @essay_grading.essay,
      conversation: payload.to_json,
      turns: Array(payload['turns']).to_json,
      student_audio_urls: Array(payload['student_audio_urls']).to_json,
      ai_audio_urls: Array(payload['ai_audio_urls']).to_json,
      duration_seconds: payload['duration_seconds']
    }.compact
  end

  def core_workflows_successful?
    @grading_success &&
      (@general_context_app_key.blank? || @general_context_success) &&
      (@revised_essay_app_key.blank? || @revised_essay_success)
  end

  def workflow_failed_steps
    steps = []
    steps << 'grading' unless @grading_success
    steps << 'general_context' if @general_context_app_key.present? && !@general_context_success
    steps << 'revised_essay' if @revised_essay_app_key.present? && !@revised_essay_success
    steps << 'speaking_scoring' if speaking_essay? && core_workflows_successful? && !@speaking_scoring_success
    steps
  end

  def workflow_stage_from_task_id(task_id)
    suffix = task_id.to_s.sub(/\A#{Regexp.escape(@essay_grading.id.to_s)}_/, '')
    suffix.presence || 'workflow'
  end

  def record_workflow_error(stage, message, **details)
    @essay_grading.record_grading_error!(stage:, message:, details:)
  rescue StandardError => e
    Rails.logger.error("[EssayGradingService] Failed to persist grading error for #{@essay_grading.id}: #{e.message}")
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
