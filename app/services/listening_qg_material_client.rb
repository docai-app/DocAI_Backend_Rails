# frozen_string_literal: true

require 'net/http'
require 'json'

# Teacher catalog transport; the answer-bearing assignment fetch remains separate.
class ListeningQgMaterialClient
  class Error < StandardError; end

  def initialize(base_url: ENV['QG_LISTENING_INTERNAL_URL'], token: ENV['QG_LISTENING_SERVICE_TOKEN'])
    @base_url, @token = base_url.to_s, token.to_s
  end

  def list(query: '', page: 1)
    request('', query: { query: query.to_s[0, 200], page: [page.to_i, 1].max })
  end

  def detail(id)
    request("/#{valid_id(id)}")
  end

  def generate_audio(id, retry_failed: false)
    request("/#{valid_id(id)}/generate_audio", body: { confirm_paid: true, retry_failed: retry_failed })
  end

  private

  def valid_id(id)
    raise Error, 'Invalid listening material' unless id.to_s.match?(/\A[1-9]\d*\z/)
    id.to_s
  end

  def request(suffix, query: nil, body: nil)
    uri = URI.parse(@base_url)
    local = uri.scheme == 'http' && %w[localhost 127.0.0.1].include?(uri.host)
    unless (uri.is_a?(URI::HTTPS) || local) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && @token.bytesize >= 32
      raise Error, 'Listening service is unavailable'
    end
    uri.path = "#{uri.path.sub(%r{/+\z}, '')}/api/v1/internal/listening_materials#{suffix}"
    uri.query = URI.encode_www_form(query) if query
    message = body ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    message['Authorization'] = "Bearer #{@token}"
    message['Content-Type'] = 'application/json'
    message['Accept'] = 'application/json'
    message.body = JSON.generate(body) if body
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 30
    http.max_retries = 0
    raw = +''
    http.request(message) do |response|
      raise Error, 'Listening material is unavailable; refresh its status before retrying' unless %w[200 202].include?(response.code)
      response.read_body do |chunk|
        raise Error, 'Invalid listening response' if raw.bytesize + chunk.bytesize > 1_048_576
        raw << chunk
      end
    end
    envelope = JSON.parse(raw)
    raise Error, 'Invalid listening response' unless envelope.is_a?(Hash) && envelope['success'] == true && envelope['data'].is_a?(Hash)
    envelope['data']
  rescue Error
    raise
  rescue StandardError
    raise Error, 'Listening service is unavailable; refresh its status before retrying'
  end
end
