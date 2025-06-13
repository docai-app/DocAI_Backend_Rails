# frozen_string_literal: true

# app/services/essay_grading_service.rb
require 'rest-client'

class EssayGradingService
  # API_URL = 'https://admin.docai.net/v1/workflows/run'
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
    # 运行 grading workflow
    grading_response = execute_workflow(@grading_app_key, grading_request_payload)
    @grading_success = process_response(grading_response, 'grading')

    # 运行 general_context workflow (如果 @general_context_app_key 不为 nil)
    unless @general_context_app_key.blank?
      general_context_response = execute_workflow(@general_context_app_key, general_context_request_payload)
      @general_context_success = process_response(general_context_response, 'general_context')
    end

    # 最终确认状态
    update_final_status
  end

  private

  def execute_workflow(app_key, payload)
    RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload:,
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

  def headers(app_key)
    {
      'Authorization' => "Bearer #{app_key}",
      'Content-Type' => 'application/json'
    }
  end

  def grading_request_payload
    inputs = if @essay_grading.essay_assignment.category == 'sentence_builder'
               { sentence_builder: @essay_grading.sentence_builder_for_dify.to_json }
             elsif is_ielts_task_1?
               build_ielts_task_1_inputs
             else
               { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
             end

    # 向後兼容：非IELTS Task 1 的圖片處理保持原有邏輯
    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph_image_url] = @essay_grading.essay_assignment.graph_image.url
      Rails.logger.info("[EssayGradingService] Including graph image URL for grading assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'blocking',
      user: @user_id
    }

    # 記錄完整的請求載荷以便調試
    Rails.logger.info("[EssayGradingService] Full request payload: #{payload.to_json}")

    payload.to_json
  end

  def general_context_request_payload
    inputs = if is_ielts_task_1?
               build_ielts_task_1_inputs
             else
               {
                 Essay: @essay_grading.essay,
                 essaytopic: @essay_grading.topic
               }
             end

    # 向後兼容：非IELTS Task 1 的圖片處理保持原有邏輯
    if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
      inputs[:graph_image_url] = @essay_grading.essay_assignment.graph_image.url
      Rails.logger.info("[EssayGradingService] Including graph image URL for general context assignment #{@essay_grading.essay_assignment.id}")
    end

    payload = {
      inputs:,
      response_mode: 'blocking',
      user: @user_id
    }

    # 記錄完整的請求載荷以便調試
    Rails.logger.info("[EssayGradingService] Full general context payload: #{payload.to_json}")

    payload.to_json
  end

  def process_response(response, context)
    return false unless response && response.code == 200

    begin
      result = JSON.parse(response.body)

      # 檢查 Dify 響應是否包含錯誤
      if result['error'].present?
        Rails.logger.error("[EssayGradingService] Dify API error: #{result['error']}")
        return false
      end

      # 檢查響應結構是否正確
      unless result['data'] && result['data']['outputs']
        Rails.logger.error("[EssayGradingService] Invalid Dify response structure: #{result}")
        return false
      end

      outputs = result['data']['outputs']
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

      true
    rescue JSON::ParserError => e
      Rails.logger.error("[EssayGradingService] Failed to parse Dify response: #{e.message}")
      Rails.logger.error("[EssayGradingService] Response body: #{response.body}")
      false
    rescue StandardError => e
      Rails.logger.error("[EssayGradingService] Error processing Dify response: #{e.message}")
      Rails.logger.error("[EssayGradingService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
      false
    end
  end

  def get_number_of_suggestion(result)
    # 檢查 result 是否為 nil 或不包含預期的結構
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
    if @grading_success && (@general_context_app_key.blank? || @general_context_success)
      @essay_grading.update(status: 'graded')

      @essay_grading.calculate_sentence_builder_score if @essay_grading.category == 'sentence_builder'

      @essay_grading.call_webhook
    else
      @essay_grading.update(status: 'stopped')
    end
  end

  # 判斷是否為 IELTS Task 1 作業
  def is_ielts_task_1?
    @essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
  end

  # 構建 IELTS Task 1 專用的 inputs 格式
  def build_ielts_task_1_inputs
    # 先上傳圖片到 Dify 獲取 upload_file_id
    graph_input = build_ielts_graph_input

    inputs = {
      graph: graph_input,
      Essay: @essay_grading.essay,
      essay_topic: @essay_grading.topic
    }

    Rails.logger.info("[EssayGradingService] Building IELTS Task 1 inputs for assignment #{@essay_grading.essay_assignment.id}")
    Rails.logger.info("[EssayGradingService] Graph input: #{graph_input}")
    Rails.logger.info("[EssayGradingService] Essay length: #{inputs[:Essay]&.length}")
    Rails.logger.info("[EssayGradingService] Topic: #{inputs[:essay_topic]}")

    inputs
  end

  # 構建 IELTS Task 1 圖片輸入格式
  def build_ielts_graph_input
    return nil unless @essay_grading.essay_assignment.graph_image.attached?

    graph_url = @essay_grading.essay_assignment.graph_image.url

    # 使用 Dify 文件上傳服務
    upload_service = DifyFileUploadService.new(@grading_app_key, @user_id)
    upload_result = upload_service.upload_from_url(graph_url, 'image')

    if upload_result.success?
      Rails.logger.info("[EssayGradingService] Successfully uploaded graph to Dify, upload_file_id: #{upload_result.upload_file_id}")

      # 返回 Dify 期望的文件數組格式 - 嘗試不同的格式
      file_input = {
        'transfer_method' => 'local_file',
        'upload_file_id' => upload_result.upload_file_id,
        'type' => 'image'
      }

      Rails.logger.info("[EssayGradingService] File input format: #{file_input}")

      # 嘗試返回數組格式，使用字符串鍵
      [file_input]
    else
      Rails.logger.error("[EssayGradingService] Failed to upload graph to Dify: #{upload_result.error_message}")
      Rails.logger.warn('[EssayGradingService] Falling back to direct URL for graph')

      # 如果上傳失敗，回退到直接使用 URL（向後兼容）
      graph_url
    end
  rescue StandardError => e
    Rails.logger.error("[EssayGradingService] Error building graph input: #{e.message}")
    Rails.logger.warn('[EssayGradingService] Falling back to direct URL for graph')

    # 發生錯誤時回退到直接使用 URL
    graph_url
  end
end
