# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require_relative '../../app/services/listening_qg_version_client'

class ListeningQgVersionClientStandaloneTest < Minitest::Test
  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :max_retries
    attr_reader :request_value
    def initialize(body, code)
      @body, @code = body, code
    end
    def request(value)
      @request_value = value
      yield self
    end
    def code
      @code
    end
    def read_body
      yield @body
    end
  end

  def payload
    { 'success' => true, 'data' => { 'version_id' => '12', 'news_feed_id' => '34', 'level' => 'A2',
      'published_at' => '2026-09-09T12:00:00Z', 'content_digest' => 'a' * 64, 'quiz' => {},
      'plain_transcript' => 'Test', 'audio_url' => 'https://storage.example/test.wav', 'audio_metadata' => {},
      'unexpected' => 'not copied' } }
  end

  def fetch(body = JSON.generate(payload), code: '200', url: 'https://qg.example')
    @http = FakeHttp.new(body, code)
    Net::HTTP.stub(:new, @http) do
      ListeningQgVersionClient.new(base_url: url, token: 'test-only-' * 4).fetch(version_id: '12', news_feed_id: '34', level: 'A2')
    end
  end

  def test_exact_selection_and_private_attribute_allowlist
    result = fetch
    assert_equal '12', result[:qg_version_id]
    refute result.key?(:unexpected)
    assert_equal '/api/v1/internal/listening_versions/12', @http.request_value.path
    assert_equal true, @http.use_ssl
    assert_equal 0, @http.max_retries
  end

  def test_no_redirects_or_non_success_responses
    %w[301 401 404 500].each do |code|
      assert_raises(ListeningQgVersionClient::Error) { fetch(code: code) }
    end
  end

  def test_mismatched_selection_and_malformed_envelopes_fail
    %w[version_id news_feed_id level published_at].each do |key|
      data = payload
      data['data'][key] = ''
      assert_raises(ListeningQgVersionClient::Error) { fetch(JSON.generate(data)) }
    end
    ['{broken', 'null', '{"success":false}', 'x' * (ListeningQgVersionClient::MAX_BYTES + 1)].each do |body|
      assert_raises(ListeningQgVersionClient::Error) { fetch(body) }
    end
  end

  def test_insecure_remote_urls_or_embedded_credentials_rejected
    ['http://qg.example', 'https://user:secret@qg.example', 'https://qg.example/?token=secret', 'file:///tmp/a'].each do |url|
      assert_raises(ListeningQgVersionClient::Error) { fetch(url: url) }
    end
    assert_equal '12', fetch(url: 'http://127.0.0.1:3100')[:qg_version_id]
  end
end
