# frozen_string_literal: true

require 'json'
require 'rest-client'

module SpeakingEssay
  class DifyScoringClient
    def initialize(
      api_key: ENV['DIFY_SPEAKING_ESSAY_SCORING_APP_KEY'],
      server: ENV.fetch('DIFY_WORKFLOW_BASE_URL', 'https://aienglish-dify.docai.net/v1')
    )
      @api_key = api_key.to_s.strip
      @server = server.to_s.delete_suffix('/')
    end

    def call(inputs:, user:)
      raise 'DIFY_SPEAKING_ESSAY_SCORING_APP_KEY is missing.' if @api_key.blank?

      response = RestClient::Request.execute(
        method: :post,
        url: "#{@server}/workflows/run",
        payload: {
          response_mode: 'blocking',
          user:,
          inputs:
        }.to_json,
        headers: {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        },
        open_timeout: 15,
        timeout: timeout_seconds
      )

      payload = JSON.parse(response.body)
      report = extract_report(payload)

      {
        speaking_report: report['speaking_report'] || report,
        raw_provider_payload: payload
      }
    rescue RestClient::ExceptionWithResponse => e
      body = e.response&.body.to_s
      raise "Dify speaking essay scoring failed: HTTP #{e.response&.code} #{body}"
    rescue JSON::ParserError => e
      raise "Dify speaking essay scoring returned invalid JSON: #{e.message}"
    end

    private

    def timeout_seconds
      ENV.fetch('SPEAKING_ESSAY_SCORING_TIMEOUT_SECONDS', '180').to_i
    end

    def extract_report(payload)
      outputs = payload.dig('data', 'outputs') || {}
      candidate = outputs['speaking_report'] ||
                  outputs['result_json'] ||
                  outputs['text'] ||
                  outputs['answer'] ||
                  outputs

      parse_report(candidate)
    end

    def parse_report(candidate)
      return candidate if candidate.is_a?(Hash)

      text = candidate.to_s.strip
      text = text.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
      JSON.parse(text)
    end
  end
end
