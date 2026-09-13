# frozen_string_literal: true

require 'net/http'
require 'json'

# A read-only lookup of the ORIGINAL workflow, never a second workflow POST.
# No run ID, missing permissions, running/paused, or an ambiguous lookup stays unknown.
class DifyWorkflowRecovery
  def self.terminal_events(events, app_key:, run_url:)
    run_id = Array(events).filter_map do |event|
      event['workflow_run_id'].presence || (event['event'] == 'workflow_started' && event.dig('data', 'id'))
    end.last
    return nil unless run_id.is_a?(String) && run_id.match?(/\A[0-9a-f-]{36}\z/i) && app_key.present?

    data = lookup(run_id, app_key: app_key, run_url: run_url)
    return nil unless data && %w[succeeded failed stopped].include?(data['status'])
    [{ 'event' => 'workflow_finished', 'data' => data }]
  end

  def self.lookup(run_id, app_key:, run_url:)
    return nil unless run_id.is_a?(String) && run_id.match?(/\A[0-9a-f-]{36}\z/i) && app_key.present?
    uri = URI("#{run_url}/#{run_id}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{app_key}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 15) { |http| http.request(request) }
    return nil unless response.code.to_i == 200

    data = JSON.parse(response.body)
    return nil unless data.is_a?(Hash) && data['id'] == run_id
    normalize_result(data)
  rescue StandardError => e
    Rails.logger.warn("[DifyWorkflowRecovery] Original workflow status unavailable: #{e.class}")
    nil
  end

  # Some deployed Dify versions serialize outputs in GET /workflows/run/:id,
  # while SSE sends the same outputs as an object. Preserve invalid/missing
  # output for normal validation; decoding is not permission to invent feedback.
  def self.normalize_result(data)
    return data unless data.is_a?(Hash) && data['outputs'].is_a?(String)

    outputs = JSON.parse(data['outputs'])
    outputs.is_a?(Hash) ? data.merge('outputs' => outputs) : data
  rescue JSON::ParserError
    data
  end

  def self.normalize_terminal_event(event)
    return event unless event.is_a?(Hash) && event['event'] == 'workflow_finished'

    event.merge('data' => normalize_result(event['data']))
  end
end
