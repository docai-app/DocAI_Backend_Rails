# frozen_string_literal: true

require 'tempfile'

module SpeakingEssay
  class AudioAnalysisService
    def initialize(essay_grading)
      @essay_grading = essay_grading
    end

    def call
      return true unless speaking_essay?
      raise 'Speaking essay audio file is missing.' unless @essay_grading.file.attached?

      with_audio_tempfile do |audio_path, content_type|
        deepgram_result = DeepgramTranscriber.new.call(audio_path:, content_type:)
        transcript_text = deepgram_result[:transcript_text].presence || @essay_grading.essay.to_s.strip
        raise 'Speaking essay transcript is blank after Deepgram transcription.' if transcript_text.blank?

        speech_metrics = SpeechMetricsBuilder.new.call(deepgram_result:)
        pronunciation_metrics = AzurePronunciationAssessor.new.call(
          audio_path:,
          reference_text: transcript_text
        )

        persist_analysis!(
          transcript_text:,
          deepgram_result:,
          speech_metrics:,
          pronunciation_metrics:
        )
      end

      true
    end

    private

    def speaking_essay?
      @essay_grading.category == 'speaking_essay'
    end

    def with_audio_tempfile
      blob = @essay_grading.file.blob
      extension = extension_from_blob(blob)
      content_type = blob.content_type.presence || content_type_from_extension(extension)

      Tempfile.create(["speaking-essay-#{@essay_grading.id}", extension], binmode: true) do |file|
        file.write(blob.download)
        file.flush

        yield file.path, content_type
      end
    end

    def extension_from_blob(blob)
      extension = File.extname(blob.filename.to_s).downcase
      return extension if extension.present?

      case blob.content_type.to_s
      when 'audio/mpeg', 'audio/mp3'
        '.mp3'
      when 'audio/mp4', 'audio/x-m4a'
        '.m4a'
      when 'audio/wav', 'audio/wave', 'audio/x-wav'
        '.wav'
      when 'audio/webm'
        '.webm'
      else
        '.audio'
      end
    end

    def content_type_from_extension(extension)
      case extension
      when '.mp3', '.mpeg'
        'audio/mpeg'
      when '.m4a', '.mp4'
        'audio/mp4'
      when '.wav'
        'audio/wav'
      when '.webm'
        'audio/webm'
      else
        'application/octet-stream'
      end
    end

    def persist_analysis!(transcript_text:, deepgram_result:, speech_metrics:, pronunciation_metrics:)
      pronunciation_payload = pronunciation_metrics.except(:raw_provider_payload)
      deepgram_payload = deepgram_result.except(:raw_provider_payload)
      azure_payload = compact_azure_payload(pronunciation_metrics)
      raw_payloads = raw_provider_payloads(deepgram_result, pronunciation_metrics)

      analysis = {
        'transcript' => {
          'text' => transcript_text,
          'segments' => deepgram_result[:segments],
          'words' => deepgram_result[:words],
          'confidence' => deepgram_result[:confidence]
        },
        'deepgram' => deepgram_payload,
        'azure_pronunciation' => azure_payload,
        'speech_metrics' => speech_metrics,
        'pronunciation_metrics' => pronunciation_payload
      }
      analysis['raw_provider_payloads'] = raw_payloads if raw_payloads.present?

      next_grading = (@essay_grading.grading || {}).deep_dup
      next_grading['speaking_analysis'] = analysis
      next_grading['speaking_transcript'] = transcript_text
      next_grading['transcript'] = analysis['transcript']
      next_grading['speech_metrics'] = speech_metrics
      next_grading['pronunciation_metrics'] = pronunciation_payload

      @essay_grading.update!(
        essay: transcript_text,
        grading: next_grading
      )
    end

    def raw_provider_payloads(deepgram_result, pronunciation_metrics)
      return {} unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('SPEAKING_ESSAY_STORE_RAW_PROVIDER_PAYLOADS', 'false'))

      {
        'deepgram' => deepgram_result[:raw_provider_payload],
        'azure_pronunciation' => pronunciation_metrics[:raw_provider_payload]
      }
    end

    def compact_azure_payload(pronunciation_metrics)
      raw = pronunciation_metrics[:raw_provider_payload]
      return pronunciation_metrics.except(:raw_provider_payload) unless raw.is_a?(Hash)

      {
        'provider_name' => raw['provider_name'],
        'mode' => raw['mode'],
        'reference_text_used' => raw['reference_text_used'],
        'segment_count' => raw['segment_count'],
        'aggregated_result' => raw['aggregated_result']
      }
    end
  end
end
