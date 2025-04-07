# frozen_string_literal: true

require 'rest-client'

class SentenceBuilderExampleService
  API_URL = 'https://aienglish-dify.docai.net/v1/workflows/run'
  TIMEOUT = 300 # Timeout duration in seconds (5 minutes)

  def initialize(user_id, essay_assignment)
    @user_id = user_id
    
    if essay_assignment.rubric == 'advanced'
      @app_key = ENV['sentence_builder_example_app_key_advanced']
    else
      @app_key = ENV['sentence_builder_example_app_key']
    end

    @vocabs = essay_assignment.vocabs.map do |vocab|
      "#{vocab['word']}(#{vocab['pos']})"
    end.join(',')
  end

  def generate_examples
    response = execute_request
    return unless response && response.code == 200

    result = JSON.parse(response.body)
    JSON.parse(result['data']['outputs']['text'])['examples']
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse response: #{e.message}")
    nil
  end

  def execute_request
    RestClient::Request.execute(
      method: :post,
      url: API_URL,
      payload: {
        inputs: {
          vocabs: @vocabs
        },
        response_mode: 'blocking',
        user: @user_id
      }.to_json,
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
end
