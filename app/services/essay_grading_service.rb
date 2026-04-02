# frozen_string_literal: true

# app/services/essay_grading_service.rb
require 'rest-client'
require 'json'
require 'net/http'

class EssayGradingService
  # API_URL = 'https://admin.docai.net/v1/workflows/run'
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  COMPLETION_API_URL = 'https://aienglish-dify.docai.net/v1/completion-messages'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @grading_app_key = essay_grading.grading['app_key']
    @general_context_app_key = essay_grading.general_context['app_key']
    @revised_essay_app_key = essay_grading.revised_essay_app_key
    @grading_success = false
    @general_context_success = false
    @revised_essay_success = false
  end

  def run_workflows
    # 运行 grading workflow
    grading_response = execute_streaming_workflow(@grading_app_key, grading_request_payload)
    @grading_success = process_response(grading_response, 'grading')

    # 运行 general_context workflow (如果 @general_context_app_key 不为 nil)
    unless @general_context_app_key.blank?
      general_context_response = execute_workflow(@general_context_app_key, general_context_request_payload)
      @general_context_success = process_response(general_context_response, 'general_context')
    end

    unless @revised_essay_app_key.blank?
      revised_essay_response = execute_completion(@revised_essay_app_key, revised_essay_completion_payload)
      @revised_essay_success = process_response(revised_essay_response, 'revised_essay')
    end

    # 最终确认状态
    update_final_status
  end

  private

  def execute_workflow(app_key, payload)
    RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload: payload.to_json,
      headers: headers(app_key),
      timeout: TIMEOUT,
      open_timeout: 100
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error("Exception when calling workflow: #{e.response}")
    nil
  rescue StandardError => e
    Rails.logger.error("Standard error when calling workflow: #{e.message}")
    nil
  end

  def execute_streaming_workflow(app_key, payload)
    uri = URI(API_URL)
    request = Net::HTTP::Post.new(uri, streaming_headers(app_key))
    request.body = payload.to_json

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = TIMEOUT
    http.open_timeout = 100

    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_file = ENV['SSL_CERT_FILE'].presence || '/etc/ssl/cert.pem'
      http.ca_file = ca_file if File.exist?(ca_file)
    end

    http.start do |client|
      response = client.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Streaming workflow HTTP error: #{response.code} #{response.message}")
        return nil
      end

      process_streaming_workflow_response(response.body.to_s)
    end
  rescue StandardError => e
    Rails.logger.error("Standard error when calling streaming workflow: #{e.class}: #{e.message}")
    nil
  end

  def headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json'
    }
  end

  def streaming_headers(app_key)
    headers(app_key).merge('Accept' => 'text/event-stream')
  end

  def grading_request_payload
    inputs = if @essay_grading.essay_assignment.category == 'sentence_builder'
               { sentence_builder: @essay_grading.sentence_builder_for_dify.to_json }
             else
               { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
             end

    {
      inputs:,
      response_mode: 'streaming',
      user: @user_id
    }
  end

  def general_context_request_payload
    {
      inputs: {
        Essay: @essay_grading.essay, # 假设 general_context 使用相同的 Essay 字段，如果不同则修改
        essaytopic: @essay_grading.topic # 同样假设 topic 字段相同，如果不同则修改
      },
      response_mode: 'blocking',
      user: @user_id
    }
  end

  def revised_essay_completion_payload
    {
      inputs: {
        essay: @essay_grading.essay,
        topic: @essay_grading.topic,
        guide: @essay_grading.essay_assignment.revised_essay_type_label
      },
      response_mode: 'blocking',
      user: @user_id
    }
  end

  def execute_completion(app_key, payload)
    RestClient::Request.execute(
      method: :post,
      url: COMPLETION_API_URL,
      payload: payload.to_json,
      headers: headers(app_key),
      timeout: TIMEOUT,
      open_timeout: 100
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error("Exception when calling completion API: #{e.response}")
    nil
  rescue StandardError => e
    Rails.logger.error("Standard error when calling completion API: #{e.message}")
    nil
  end

  def process_response(response, context)
    return false unless response && response.code == 200

    result = JSON.parse(response.body)
    if result.dig('data', 'status').present? && result.dig('data', 'status') != 'succeeded'
      Rails.logger.error("#{context} workflow returned non-succeeded status: #{result.dig('data', 'status')} / #{result.dig('data', 'error')}")
      return false
    end

    num_of_suggestions = get_number_of_suggestion(result['data']['outputs']) if context == 'grading'

    if context == 'grading'
      return false if result.dig('data', 'outputs').blank?

      @essay_grading.update(
        grading: @essay_grading.grading.merge('data' => result['data']['outputs'],
                                              'number_of_suggestion' => num_of_suggestions)
      )
    elsif context == 'general_context'
      return false if result.dig('data', 'outputs').blank?

      @essay_grading.update(
        general_context: @essay_grading.general_context.merge('data' => result['data']['outputs'])
      )
    elsif context == 'revised_essay'
      revised_outputs =
        if result.dig('data', 'outputs').present?
          result['data']['outputs']
        elsif result['answer'].present?
          { 'text' => result['answer'] }
        end

      return false if revised_outputs.blank?

      @essay_grading.update(
        revised_essay: @essay_grading.revised_essay.merge('data' => revised_outputs)
      )
    end

    true
  end

  def process_streaming_workflow_response(response_body)
    finished_payload = nil

    response_body.to_s.each_line do |raw_line|
      line = raw_line.strip
      next if line.empty? || !line.start_with?('data: ')

      begin
        data = JSON.parse(line.delete_prefix('data: ').strip)
      rescue JSON::ParserError
        next
      end

      case data['event']
      when 'workflow_finished'
        finished_payload = data['data']
        break
      when 'workflow_failed'
        Rails.logger.error("Streaming workflow failed event: #{data}")
      end
    end

    return nil if finished_payload.blank?

    Struct.new(:code, :body).new(200, { data: finished_payload }.to_json)
  end

  def get_number_of_suggestion(result)
    json = JSON.parse(result['text'])
    if @essay_grading.category == 'sentence_builder'
      count_sentence_builder_errors(json)
    else
      count_errors(json)
    end
  end

  def count_sentence_builder_errors(hash)
    count = 0
    hash['results'].each do |result|
      if result['errors'].is_a?(Array)
        # 只計算 error1 不等於 'Correct' 的錯誤
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
       (@revised_essay_app_key.blank? || @revised_essay_success)
      @essay_grading.update(status: 'graded')

      @essay_grading.calculate_sentence_builder_score if @essay_grading.category == 'sentence_builder'

      @essay_grading.call_webhook
    else
      @essay_grading.update(status: 'stopped')
    end
  end
end
