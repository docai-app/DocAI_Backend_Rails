# frozen_string_literal: true

require 'rest-client'

# Service to generate sample essays for IELTS assignments using Dify workflow
class SampleEssayGenerationService
  # 定義結果結構
  Result = Struct.new(:success?, :sample_essay, :error_message, keyword_init: true)

  # Dify API 配置
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  TIMEOUT = 300 # seconds

  def initialize(essay_assignment)
    @essay_assignment = essay_assignment
    @user_id = essay_assignment.general_user_id
    @app_key = determine_app_key
    @logger = Rails.logger
  end

  def call
    # 檢查是否有有效的API Key
    unless @app_key
      @logger.error("[SampleEssayGenerationService] Missing API key for assignment #{@essay_assignment.id}")
      return Result.new(success?: false, error_message: 'Missing API key for sample essay generation.')
    end

    response = execute_request
    process_response(response)
  rescue StandardError => e
    @logger.error("[SampleEssayGenerationService] Unexpected error for assignment #{@essay_assignment.id}: #{e.message}\n#{e.backtrace.join("\n")}")
    Result.new(success?: false, error_message: 'An unexpected error occurred during sample essay generation.')
  end

  private

  # 確定使用哪個API Key - 統一使用環境變量
  def determine_app_key
    # 統一使用環境變量，符合業務邏輯：sample essay 是後續生成的功能
    ENV.fetch('SAMPLE_ESSAY_GENERATION_APP_KEY', nil)
  end

  # 執行HTTP請求到Dify API
  def execute_request
    RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload: request_payload.to_json,
      headers: request_headers,
      timeout: TIMEOUT,
      open_timeout: 10
    )
  rescue RestClient::ExceptionWithResponse => e
    @logger.error("[SampleEssayGenerationService] API request failed for assignment #{@essay_assignment.id}: #{e.response}")
    nil
  rescue RestClient::Exceptions::Timeout, Errno::ECONNREFUSED => e
    @logger.error("[SampleEssayGenerationService] API connection/timeout error for assignment #{@essay_assignment.id}: #{e.message}")
    nil
  end

  # 處理API響應
  def process_response(response)
    unless response && response.code == 200
      return Result.new(success?: false, error_message: 'Failed to communicate with the sample essay generation API.')
    end

    begin
      api_result = JSON.parse(response.body)
      # 假設Dify返回的結構是 {'data' => {'outputs' => {'text' => 'generated_sample_essay'}}}
      sample_essay_text = api_result.dig('data', 'outputs', 'text')

      if sample_essay_text.present?
        Result.new(success?: true, sample_essay: sample_essay_text)
      else
        @logger.error("[SampleEssayGenerationService] Empty sample essay returned for assignment #{@essay_assignment.id}")
        Result.new(success?: false, error_message: 'Empty sample essay generated.')
      end
    rescue JSON::ParserError => e
      @logger.error("[SampleEssayGenerationService] Failed to parse API response for assignment #{@essay_assignment.id}: #{e.message}. Response body: #{response.body}")
      Result.new(success?: false, error_message: 'Invalid response format from the sample essay generation API.')
    end
  end

  # 構建API請求的payload
  def request_payload
    inputs = {
      essaytopic: @essay_assignment.topic || @essay_assignment.title,
      assignment_details: @essay_assignment.assignment
    }

    # 如果有圖片附件，添加圖片URL - 這是IELTS看圖作文的關鍵功能
    if @essay_assignment.graph_image.attached?
      inputs[:graph_image_url] = @essay_assignment.graph_image.url
      @logger.info("[SampleEssayGenerationService] Including graph image URL for assignment #{@essay_assignment.id}")
    end

    {
      inputs:,
      response_mode: 'blocking',
      user: @user_id
    }
  end

  # 構建API請求的headers
  def request_headers
    {
      'Authorization' => "Bearer #{@app_key}",
      'Content-Type' => 'application/json'
    }
  end
end
