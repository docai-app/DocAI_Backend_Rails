# frozen_string_literal: true

require 'base64'
require 'stringio'

class SpeakingConversationAudioStorageService
  class << self
    def upload!(base64_or_data_url:, filename_prefix:)
      payload, content_type = decode_payload(base64_or_data_url)
      return nil if payload.blank?

      extension = extension_for_content_type(content_type)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(payload),
        filename: "#{filename_prefix}_#{SecureRandom.hex(8)}.#{extension}",
        content_type: content_type,
        service_name: ApplicationRecord.preferred_microsoft_storage_service
      )
      blob.url
    end

    def persist_data_url!(url_or_data, filename_prefix:)
      return url_or_data unless url_or_data.is_a?(String)
      return url_or_data unless url_or_data.start_with?('data:')

      upload!(base64_or_data_url: url_or_data, filename_prefix: filename_prefix)
    end

    private

    def decode_payload(value)
      return [nil, nil] if value.blank?

      if value.start_with?('data:')
        header, encoded = value.split(',', 2)
        content_type = header[%r{data:([^;]+)}, 1]
        [Base64.decode64(encoded.to_s), content_type]
      else
        [Base64.decode64(value.to_s), 'audio/mpeg']
      end
    rescue ArgumentError
      [nil, nil]
    end

    def extension_for_content_type(content_type)
      case content_type.to_s
      when 'audio/wav', 'audio/x-wav'
        'wav'
      when 'audio/mpeg', 'audio/mp3'
        'mp3'
      when 'audio/webm'
        'webm'
      else
        'bin'
      end
    end
  end
end
