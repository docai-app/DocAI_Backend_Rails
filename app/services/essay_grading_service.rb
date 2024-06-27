# app/services/essay_grading_service.rb
require 'rest-client'

class EssayGradingService
  API_URL = 'https://admin.docai.net/v1/workflows/run'

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @api_key = essay_grading.app_key
  end

  def run_workflow
    response = RestClient.post(API_URL, request_payload, headers)

    if response.code == 200
      result = JSON.parse(response.body)
      update_essay_grading(result['data']['outputs'])
    else
      Rails.logger.error("Failed to run workflow: #{response.code}, #{response.body}")
    end
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error("Exception when calling workflow: #{e.response}")
  end

  private

  def request_payload
    {
      inputs: {
        Essay: @essay_grading.essay,
        essaytopic: @essay_grading.topic
      },
      response_mode: 'blocking',
      user: @user_id
    }.to_json
  end

  def headers
    {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def update_essay_grading(result)
    @essay_grading.update(grading: @essay_grading.grading.merge('data' => result), status: 'graded')
  end
end