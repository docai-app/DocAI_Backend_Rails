# frozen_string_literal: true

require 'json'
require 'net/http'
require 'rest-client'
require 'securerandom'
require 'uri'

module SpeakingEssay
  class DifyScoringClient
    DEFAULT_RESPONSE_MODE = 'streaming'
    MAX_STREAMING_RETRIES = 3

    def initialize(
      api_key: ENV['DIFY_SPEAKING_ESSAY_SCORING_APP_KEY'],
      server: ENV.fetch('DIFY_WORKFLOW_BASE_URL', 'https://aienglish-dify.docai.net/v1'),
      response_mode: ENV.fetch('DIFY_SPEAKING_ESSAY_SCORING_RESPONSE_MODE', DEFAULT_RESPONSE_MODE)
    )
      @api_key = api_key.to_s.strip
      @server = server.to_s.delete_suffix('/')
      @response_mode = response_mode.to_s.strip.downcase
    end

    def call(inputs:, user:)
      raise 'DIFY_SPEAKING_ESSAY_SCORING_APP_KEY is missing.' if @api_key.blank?

      if @response_mode == 'blocking'
        call_blocking(inputs:, user:)
      else
        call_streaming(inputs:, user:)
      end
    end

    private

    def call_streaming(inputs:, user:)
      payload = workflow_payload(inputs:, user:, response_mode: 'streaming')
      chunks, task_id = execute_workflow_streaming(payload, user:)
      report, outputs = extract_report_from_chunks(chunks)

      unless report
        Rails.logger.warn(
          "[SpeakingEssay::DifyScoringClient] Streaming produced no report (chunks=#{chunks.size}), " \
          "falling back to blocking, task_id=#{task_id}"
        )
        return call_blocking(inputs:, user:)
      end

      {
        speaking_report: report['speaking_report'] || report,
        raw_provider_payload: {
          'response_mode' => 'streaming',
          'task_id' => task_id,
          'chunk_count' => chunks.size,
          'workflow_finished' => chunks.find { |c| c['event'] == 'workflow_finished' },
          'outputs' => outputs,
          'chunks' => store_streaming_chunks? ? chunks : nil
        }.compact
      }
    end

    def call_blocking(inputs:, user:)
      payload = workflow_payload(inputs:, user:, response_mode: 'blocking')
      response = RestClient::Request.execute(
        method: :post,
        url: workflow_run_url,
        payload: payload.to_json,
        headers: blocking_headers,
        open_timeout: open_timeout_seconds,
        timeout: blocking_timeout_seconds
      )

      body = JSON.parse(response.body)
      report = extract_report(body)

      {
        speaking_report: report['speaking_report'] || report,
        raw_provider_payload: body.merge('response_mode' => 'blocking')
      }
    rescue RestClient::ExceptionWithResponse => e
      body = e.response&.body.to_s
      raise "Dify speaking essay scoring failed: HTTP #{e.response&.code} #{body}"
    rescue JSON::ParserError => e
      raise "Dify speaking essay scoring returned invalid JSON: #{e.message}"
    end

    def execute_workflow_streaming(payload, user:)
      task_id = "#{user}_#{SecureRandom.hex(4)}"
      retries = 0

      begin
        chunks = stream_workflow_sse(payload, task_id:)
        [chunks, task_id]
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError => e
        retries += 1
        if retries <= MAX_STREAMING_RETRIES
          Rails.logger.warn(
            "[SpeakingEssay::DifyScoringClient] Streaming retry #{retries}/#{MAX_STREAMING_RETRIES} " \
            "(#{e.class}: #{e.message}), task_id=#{task_id}"
          )
          sleep(2**retries)
          retry
        end

        Rails.logger.error(
          "[SpeakingEssay::DifyScoringClient] Streaming failed after retries, fallback blocking, " \
          "task_id=#{task_id}: #{e.message}"
        )
        blocking_result = call_blocking(inputs: payload[:inputs], user: payload[:user])
        # Return synthetic chunk so extract_report_from_chunks can parse blocking body shape
        [[{ 'event' => 'workflow_finished', 'data' => blocking_result[:raw_provider_payload]['data'] || blocking_result[:raw_provider_payload] }], task_id]
      rescue Net::ReadTimeout => e
        Rails.logger.error(
          "[SpeakingEssay::DifyScoringClient] Streaming read timeout, fallback blocking, task_id=#{task_id}: #{e.message}"
        )
        blocking_result = call_blocking(inputs: payload[:inputs], user: payload[:user])
        [[{ 'event' => 'workflow_finished', 'data' => blocking_result[:raw_provider_payload]['data'] || blocking_result[:raw_provider_payload] }], task_id]
      end
    end

    def stream_workflow_sse(payload, task_id:)
      uri = URI(workflow_run_url)
      http = build_http(uri)
      request = Net::HTTP::Post.new(uri.request_uri, streaming_headers)
      request.body = payload.to_json

      chunks = []

      http.request(request) do |response|
        unless response.code.to_i == 200
          raise "Dify streaming HTTP #{response.code}: #{response.body.to_s.truncate(500)}"
        end

        buffer = +''
        response.read_body do |chunk|
          next if chunk.nil? || chunk.empty?

          buffer << chunk.dup

          while (index = buffer.index("\n\n"))
            event = buffer.slice!(0, index + 2).strip
            next if event.blank?

            parse_sse_event(event).each { |data| chunks << data }
          end
        end

        unless buffer.strip.empty?
          parse_sse_event(buffer.strip).each { |data| chunks << data }
        end
      end

      Rails.logger.info(
        "[SpeakingEssay::DifyScoringClient] Streaming finished, task_id=#{task_id}, chunks=#{chunks.size}"
      )
      chunks
    end

    def parse_sse_event(event)
      events = []
      event.each_line do |line|
        line = line.strip
        next if line.blank? || line.start_with?('event:') || line.start_with?(':')

        next unless line.start_with?('data:')

        json_str = line.sub(/^data:\s*/, '').strip
        next if json_str.blank?

        begin
          events << JSON.parse(json_str)
        rescue JSON::ParserError => e
          Rails.logger.warn(
            "[SpeakingEssay::DifyScoringClient] Skip invalid SSE JSON: #{e.message}, snippet=#{json_str.truncate(200)}"
          )
        end
      end
      events
    end

    def extract_report_from_chunks(chunks)
      return [nil, nil] if chunks.blank?

      workflow_finished_chunks = chunks.select { |c| c['event'] == 'workflow_finished' && c['data'].is_a?(Hash) }
      workflow_finished_chunks.each do |chunk|
        error = chunk.dig('data', 'error')
        raise "Dify speaking essay scoring failed: #{error}" if error.present?

        outputs = chunk['data']['outputs']
        report = extract_report_from_outputs(outputs)
        return [report, outputs] if report
      end

      node_chunks = chunks.select { |c| c['event'] == 'node_finished' && c.dig('data', 'outputs').present? }
      node_chunks.reverse_each do |chunk|
        outputs = chunk['data']['outputs']
        report = extract_report_from_outputs(outputs)
        return [report, outputs] if report
      end

      text_chunks = chunks.select { |c| c['event'] == 'text_chunk' && c['data'].present? }
      if text_chunks.any?
        combined = text_chunks.map { |c| c['data'].is_a?(String) ? c['data'] : c['data'].to_json }.join
        report = parse_report(combined)
        return [report, { 'text' => combined }] if report
      end

      error_chunk = chunks.find { |c| c['event'] == 'error' || c.dig('data', 'error').present? }
      if error_chunk
        message = error_chunk['message'] || error_chunk.dig('data', 'error') || error_chunk.to_json
        raise "Dify speaking essay scoring failed: #{message}"
      end

      [nil, nil]
    end

    def extract_report(payload)
      outputs = payload.dig('data', 'outputs') || payload['outputs'] || {}
      extract_report_from_outputs(outputs) || parse_report(outputs)
    end

    def extract_report_from_outputs(outputs)
      return nil unless outputs.is_a?(Hash)

      candidate = outputs['speaking_report'] ||
                  outputs['result_json'] ||
                  outputs['text'] ||
                  outputs['answer'] ||
                  outputs

      parse_report(candidate)
    rescue JSON::ParserError
      nil
    end

    def parse_report(candidate)
      return candidate if candidate.is_a?(Hash)
      return nil if candidate.blank?

      text = candidate.to_s.strip
      text = text.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
      JSON.parse(text)
    end

    def workflow_payload(inputs:, user:, response_mode:)
      {
        inputs: inputs,
        response_mode: response_mode,
        user: user
      }
    end

    def workflow_run_url
      "#{@server}/workflows/run"
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = open_timeout_seconds
      http.read_timeout = streaming_read_timeout_seconds
      http
    end

    def streaming_headers
      {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'text/event-stream'
      }
    end

    def blocking_headers
      {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def open_timeout_seconds
      ENV.fetch('DIFY_SPEAKING_ESSAY_OPEN_TIMEOUT_SECONDS', '15').to_i
    end

    def streaming_read_timeout_seconds
      # 流式按 chunk 刷新，单次 read 间隔可较长，避免长 LLM 推理被误判超时
      ENV.fetch('DIFY_SPEAKING_ESSAY_STREAMING_READ_TIMEOUT_SECONDS', '600').to_i
    end

    def blocking_timeout_seconds
      ENV.fetch('SPEAKING_ESSAY_SCORING_TIMEOUT_SECONDS', '300').to_i
    end

    def store_streaming_chunks?
      ActiveModel::Type::Boolean.new.cast(
        ENV.fetch('SPEAKING_ESSAY_STORE_DIFY_STREAMING_CHUNKS', 'false')
      )
    end
  end
end
