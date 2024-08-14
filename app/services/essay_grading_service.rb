# frozen_string_literal: true

# app/services/essay_grading_service.rb
require 'rest-client'

class EssayGradingService
  API_URL = 'https://admin.docai.net/v1/workflows/run'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)

  def initialize(user_id, essay_grading)
    @user_id = user_id
    @essay_grading = essay_grading
    @api_key = essay_grading.app_key
  end

  def run_workflow
    # response = RestClient.post(API_URL, request_payload, headers)
    response = RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload: request_payload,
      headers:,
      timeout: TIMEOUT,
      open_timeout: 10
    )

    puts "Response: #{response}"

    if response.code == 200
      result = JSON.parse(response.body)
      num_of_suggestions = get_number_of_suggestion(result['data']['outputs'])
      update_essay_grading(result['data']['outputs'], num_of_suggestions)
    else
      # Rails.logger.error("Failed to run workflow: #{response.code}, #{response.body}")
      update_stop_essay_grading
    end
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error("Exception when calling workflow: #{e.response}")
    update_stop_essay_grading
  rescue StandardError
    update_stop_essay_grading
  rescue StandardError
    update_stop_essay_grading
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

  def get_number_of_suggestion(result)
    json = JSON.parse(result['text'])
    count_errors(json)
  end

  def update_essay_grading(result, num_of_suggestions)
    @essay_grading.update(
      grading: @essay_grading.grading.merge('data' => result,
                                            'number_of_suggestion' => num_of_suggestions), status: 'graded'
    )
  end

  def update_stop_essay_grading
    @essay_grading.update(status: 'stopped')
  end
end
