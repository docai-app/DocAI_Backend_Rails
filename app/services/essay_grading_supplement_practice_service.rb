# frozen_string_literal: true

require 'rest-client'

class EssayGradingSupplementPracticeService
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @essay = essay_grading.essay
    @app_key = ENV['essay_grading_supplement_practice_app_key']
  end

  def run_workflow
    response = execute_request(request_payload)
    process_response(response)
  end

  private

  def execute_request(payload)
    RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload:,
      headers:,
      timeout: TIMEOUT,
      open_timeout: 100
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error("Exception when calling API: #{e.response}")
    nil
  rescue StandardError => e
    Rails.logger.error("Standard error when calling API: #{e.message}")
    nil
  end

  def headers
    {
      'Authorization' => "Bearer #{@app_key}",
      'Content-Type' => 'application/json'
    }
  end

  def request_payload
    {
      inputs: { essay: @essay },
      response_mode: 'blocking',
      user: @user_id
    }.to_json
  end

  def process_response(response)
    return unless response && response.code == 200

    result = JSON.parse(response.body)
    # result['data']['outputs']

    @essay_grading.grading['supplement_practice'] = result['data']['outputs']
    @essay_grading.save
  end
end
