# frozen_string_literal: true

# Read-only check against an already uploaded test fixture. No Rails boot, DB
# access, upload, ACL change or URL/credential logging.
require 'logger'
require 'azure/storage/blob'
require_relative '../app/services/listening_audio_reader'

abort 'Usage: ruby script/listening_audio_read_smoke.rb AUDIO SSML --read-existing-test-container' unless
  ARGV.length == 3 && ARGV[2] == '--read-existing-test-container'

begin
  audio = File.binread(ARGV[0])
  digest = Digest::SHA256.hexdigest(File.binread(ARGV[1]))
  key = "listening/azure/#{digest}/riff-24khz-16bit-mono-pcm.wav"
  account = ENV.fetch('AZURE_STORAGE_NAME')
  container = ENV.fetch('AZURE_STORAGE_CONTAINER')
  snapshot = Struct.new(:audio_url, :audio_metadata).new(
    "https://#{account}.blob.core.windows.net/#{container}/#{key}",
    { 'storage_key' => key, 'byte_size' => audio.bytesize, 'sha256' => Digest::SHA256.hexdigest(audio) }
  )
  received = ListeningAudioReader.new(account: account, container: container).read(snapshot)
  abort 'Read-back comparison failed' unless received == audio
  puts "Azure read verified: #{received.bytesize} bytes; SHA256 #{Digest::SHA256.hexdigest(received)}"
rescue StandardError => error
  warn "Read smoke failed (#{error.class}); no storage URL or credentials logged"
  exit 1
end
