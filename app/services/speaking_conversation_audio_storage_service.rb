# frozen_string_literal: true

require 'base64'
require 'stringio'

class SpeakingConversationAudioStorageService
  class << self
    def upload!(base64_or_data_url:, filename_prefix:)
      payload, content_type = decode_payload(base64_or_data_url)
      if payload.blank?
        Rails.logger.warn('[SpeakingConversationAudioStorageService] Upload skipped: decoded audio payload is blank')
        return nil
      end

      extension = extension_for_content_type(content_type)
      filename = "#{filename_prefix}_#{SecureRandom.hex(8)}.#{extension}"

      if azure_storage_configured?
        AzureService.uploadBlob(payload, filename, content_type)
      else
        upload_with_active_storage!(payload, filename, content_type)
      end
    rescue StandardError => e
      Rails.logger.error(
        "[SpeakingConversationAudioStorageService] Upload failed for #{filename_prefix}: #{e.class} #{e.message}"
      )
      nil
    end

    def persist_data_url!(url_or_data, filename_prefix:)
      return url_or_data unless url_or_data.is_a?(String)
      return url_or_data unless url_or_data.start_with?('data:')

      upload!(base64_or_data_url: url_or_data, filename_prefix: filename_prefix)
    end

    private

    def azure_storage_configured?
      [
        ENV['AZURE_STORAGE_NAME'],
        ENV['AZURE_STORAGE_ACCESS_KEY'],
        ENV['AZURE_STORAGE_CONTAINER']
      ].all?(&:present?)
    end

    def upload_with_active_storage!(payload, filename, content_type)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(payload),
        filename: filename,
        content_type: content_type,
        service_name: ApplicationRecord.preferred_microsoft_storage_service
      )

      url = blob.url
      return url if url.is_a?(String) && url.start_with?('http')

      host = ENV.fetch('RAILS_PUBLIC_HOST', 'localhost:3001')
      protocol = host.start_with?('https://') || ENV.fetch('RAILS_PUBLIC_PROTOCOL', 'http') == 'https' ? 'https' : 'http'
      normalized_host = host.sub(%r{\Ahttps?://}, '')

      Rails.application.routes.url_helpers.rails_blob_url(
        blob,
        host: normalized_host,
        protocol: protocol
      )
    end

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
