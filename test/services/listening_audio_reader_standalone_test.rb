# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require_relative '../../app/services/listening_audio_reader'

class ListeningAudioReaderStandaloneTest < Minitest::Test
  Snapshot = Struct.new(:audio_url, :audio_metadata)

  def setup
    @bytes = 'audio' * 20
    @key = "listening/azure/#{'a' * 64}/riff-24khz-16bit-mono-pcm.wav"
    @snapshot = Snapshot.new("https://localtest.blob.core.windows.net/listening-audio/#{@key}", {
      'storage_key' => @key, 'byte_size' => @bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(@bytes)
    })
    @client = Minitest::Mock.new
    @reader = ListeningAudioReader.new(client: @client, account: 'localtest', container: 'listening-audio')
  end

  def test_reads_only_expected_range_and_verifies_content
    @client.expect(:get_blob, [nil, @bytes], ['listening-audio', @key,
      { start_range: 0, end_range: 99, timeout: 30 }])
    assert_equal @bytes, @reader.read(@snapshot)
    @client.verify
  end

  def test_rejects_arbitrary_url_before_network_access
    @snapshot.audio_url = 'https://example.invalid/private'
    assert_raises(ListeningAudioReader::Unavailable) { @reader.read(@snapshot) }
    @client.verify
  end

  def test_rejects_changed_audio
    @client.expect(:get_blob, [nil, 'other' * 20], ['listening-audio', @key,
      { start_range: 0, end_range: 99, timeout: 30 }])
    assert_raises(ListeningAudioReader::Unavailable) { @reader.read(@snapshot) }
    @client.verify
  end

  def test_sdk_failure_is_sanitized_and_not_retried_by_reader
    client = Object.new
    calls = 0
    client.define_singleton_method(:get_blob) do |*|
      calls += 1
      raise Timeout::Error, 'private signed URL must not escape'
    end
    reader = ListeningAudioReader.new(client: client, account: 'localtest', container: 'listening-audio')
    error = assert_raises(ListeningAudioReader::Unavailable) { reader.read(@snapshot) }
    assert_equal 'Listening audio could not be loaded', error.message
    assert_equal 1, calls
  end
end
