# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class ListeningQgVersionClient
  class Error < StandardError; end
  MAX_BYTES = 1_048_576

  def initialize(base_url: ENV['QG_LISTENING_INTERNAL_URL'], token: ENV['QG_LISTENING_SERVICE_TOKEN'])
    @base_url, @token = base_url.to_s, token.to_s
  end

  def fetch(version_id:, news_feed_id:, level:)
    unless version_id.to_s.match?(/\A[1-9]\d*\z/) && news_feed_id.to_s.match?(/\A[1-9]\d*\z/) && %w[A2 B2 C2].include?(level)
      raise Error, 'Invalid listening selection'
    end
    uri = URI.parse(@base_url)
    local_http = uri.is_a?(URI::HTTP) && uri.scheme == 'http' && %w[127.0.0.1 localhost].include?(uri.host)
    unless (uri.is_a?(URI::HTTPS) || local_http) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && @token.bytesize >= 32
      raise Error, 'Listening QG service is not configured'
    end
    uri.path = "#{uri.path.sub(%r{/+\z}, '')}/api/v1/internal/listening_versions/#{version_id}"
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Accept'] = 'application/json'
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 30
    http.max_retries = 0
    body = +''
    http.request(request) do |response|
      raise Error, 'Listening version is unavailable' unless response.code == '200'
      response.read_body do |chunk|
        raise Error, 'Listening response is too large' if body.bytesize + chunk.bytesize > MAX_BYTES
        body << chunk
      end
    end
    envelope = JSON.parse(body)
    data = envelope.is_a?(Hash) && envelope['success'] == true && envelope['data']
    unless data.is_a?(Hash) && data['version_id'] == version_id.to_s &&
        data['news_feed_id'] == news_feed_id.to_s && data['level'] == level &&
        data['published_at'].is_a?(String) && !data['published_at'].empty?
      raise Error, 'Listening version does not match selection'
    end
    # Never merge the whole provider response into assignment params or meta.
    { qg_version_id: data['version_id'], content_digest: data['content_digest'], level: data['level'],
      quiz: data['quiz'], plain_transcript: data['plain_transcript'],
      audio_url: data['audio_url'], audio_metadata: data['audio_metadata'] }
  rescue Error
    raise
  rescue StandardError
    # Transport/parser messages can include remote content or credentials.
    raise Error, 'Listening QG request failed'
  end
end
