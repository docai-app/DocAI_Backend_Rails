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
    inputs = if is_ielts_task_1?
               build_ielts_task_1_inputs
             else
               build_standard_inputs
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

  # 判斷是否為 IELTS Task 1 作業
  def is_ielts_task_1?
    @essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
  end

  # 構建 IELTS Task 1 專用的 inputs 格式
  def build_ielts_task_1_inputs
    # 先上傳圖片到 Dify 獲取 upload_file_id
    graph_input = build_ielts_graph_input

    inputs = {
      graph: graph_input,
      Essay: 'Sample Essay Content', # Sample Essay 不需要實際作文內容
      essay_topic: @essay_assignment.topic || @essay_assignment.title
    }

    @logger.info("[SampleEssayGenerationService] Building IELTS Task 1 inputs for assignment #{@essay_assignment.id}")
    @logger.info("[SampleEssayGenerationService] Graph input: #{graph_input}")
    @logger.info("[SampleEssayGenerationService] Topic: #{inputs[:essay_topic]}")

    inputs
  end

  # 構建 IELTS Task 1 圖片輸入格式
  def build_ielts_graph_input
    return nil unless @essay_assignment.graph_image.attached?

    graph_url = @essay_assignment.graph_image.url

    # 使用 Dify 文件上傳服務
    upload_service = DifyFileUploadService.new(@app_key, @user_id)
    upload_result = upload_service.upload_from_url(graph_url, 'image')

    if upload_result.success?
      @logger.info("[SampleEssayGenerationService] Successfully uploaded graph to Dify, upload_file_id: #{upload_result.upload_file_id}")

      # 返回 Dify 期望的文件數組格式
      [{
        transfer_method: 'local_file',
        upload_file_id: upload_result.upload_file_id,
        type: 'image'
      }]
    else
      @logger.error("[SampleEssayGenerationService] Failed to upload graph to Dify: #{upload_result.error_message}")
      @logger.warn('[SampleEssayGenerationService] Falling back to direct URL for graph')

      # 如果上傳失敗，回退到直接使用 URL（向後兼容）
      [{
        transfer_method: 'remote_url',
        url: graph_url,
        type: 'image'
      }]
    end
  rescue StandardError => e
    @logger.error("[SampleEssayGenerationService] Error building graph input: #{e.message}")
    @logger.warn('[SampleEssayGenerationService] Falling back to direct URL for graph')

    # 發生錯誤時回退到直接使用 URL
    [{
      transfer_method: 'remote_url',
      url: graph_url,
      type: 'image'
    }]
  end

  # 構建標準 inputs 格式（向後兼容）
  def build_standard_inputs
    inputs = {
      essaytopic: @essay_assignment.topic || @essay_assignment.title,
      assignment_details: @essay_assignment.assignment
    }

    # 向後兼容：非IELTS Task 1 的圖片處理保持原有邏輯
    if @essay_assignment.graph_image.attached?
      inputs[:graph_image_url] = @essay_assignment.graph_image.url
      @logger.info("[SampleEssayGenerationService] Including graph image URL for assignment #{@essay_assignment.id}")
    end

    inputs
  end
end
