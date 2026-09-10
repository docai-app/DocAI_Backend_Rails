# frozen_string_literal: true

require 'digest'
require 'timeout'

# Server-only reader. Never fetch the snapshot URL as an arbitrary HTTP target.
class ListeningAudioReader
  class Unavailable < StandardError; end
  MAX_BYTES = 30 * 1024 * 1024
  READ_DEADLINE_SECONDS = 45
  KEY_PATTERN = %r{\Alistening/azure/[0-9a-f]{64}/riff-24khz-16bit-mono-pcm\.wav\z}

  def initialize(client: nil, account: ENV['QG_LISTENING_AZURE_STORAGE_NAME'] || ENV['AZURE_STORAGE_NAME'],
                 container: ENV['QG_LISTENING_STORAGE_CONTAINER'])
    @client = client
    @account = account.to_s
    @container = container.to_s
  end

  def read(snapshot)
    metadata = snapshot.audio_metadata
    raise Unavailable, 'Listening audio is unavailable' unless metadata.is_a?(Hash)
    key = metadata['storage_key'].to_s
    size = metadata['byte_size']
    sha = metadata['sha256'].to_s
    unless @account.match?(/\A[a-z0-9]{3,24}\z/) &&
           @container.match?(/\A[a-z0-9](?:[a-z0-9-]{1,61})[a-z0-9]\z/) &&
           key.match?(KEY_PATTERN) && size.is_a?(Integer) && size.between?(44, MAX_BYTES) &&
           sha.match?(/\A[0-9a-f]{64}\z/) &&
           snapshot.audio_url == "https://#{@account}.blob.core.windows.net/#{@container}/#{key}"
      raise Unavailable, 'Listening audio configuration or metadata is invalid'
    end
    client = @client || Azure::Storage::Blob::BlobService.create(
      storage_account_name: @account, storage_access_key: ENV['QG_LISTENING_AZURE_STORAGE_ACCESS_KEY'] || ENV.fetch('AZURE_STORAGE_ACCESS_KEY'))
    # Request at most the expected size. SHA validation rejects truncation or
    # changed content before any bytes are returned to the student endpoint.
    # SDK :timeout is an Azure query parameter, not a client deadline. Bound
    # this read-only network call including any SDK connection/retry waits.
    _, bytes = Timeout.timeout(READ_DEADLINE_SECONDS) do
      client.get_blob(@container, key, { start_range: 0, end_range: size - 1, timeout: 30 })
    end
    unless bytes.is_a?(String) && bytes.bytesize == size && Digest::SHA256.hexdigest(bytes) == sha
      raise Unavailable, 'Listening audio integrity check failed'
    end
    bytes
  rescue Unavailable
    raise
  rescue StandardError
    # SDK errors may contain account URLs or authorization details.
    raise Unavailable, 'Listening audio could not be loaded'
  end
end
