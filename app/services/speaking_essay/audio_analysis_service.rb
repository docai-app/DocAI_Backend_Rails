# frozen_string_literal: true

require 'tempfile'

module SpeakingEssay
  class AudioAnalysisService
    BLANK_TRANSCRIPT_MESSAGE = 'Speaking essay transcript is blank after Deepgram transcription.'
    MISSING_AUDIO_MESSAGE = 'Speaking essay audio file is missing.'

    def initialize(essay_grading)
      @essay_grading = essay_grading
    end

    def call
      return true unless speaking_essay?

      unless @essay_grading.file.attached?
        stop_for_audio_analysis_failure!(
          message: MISSING_AUDIO_MESSAGE,
          details: { error_class: 'MissingAudio' }
        )
        return false
      end

      with_audio_tempfile do |audio_path, content_type|
        deepgram_result = DeepgramTranscriber.new.call(audio_path:, content_type:)
        transcript_text = deepgram_result[:transcript_text].presence || @essay_grading.essay.to_s.strip
        if transcript_text.blank?
          stop_for_audio_analysis_failure!(
            message: BLANK_TRANSCRIPT_MESSAGE,
            details: {
              error_class: 'BlankTranscript',
              deepgram_transcript: deepgram_result[:transcript_text].to_s,
              essay_fallback_present: @essay_grading.essay.to_s.strip.present?
            }
          )
          return false
        end

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
    rescue StandardError => e
      Rails.logger.error("[SpeakingEssay::AudioAnalysisService] Failed for essay_grading #{@essay_grading.id}: #{e.message}")
      Rails.logger.error("[SpeakingEssay::AudioAnalysisService] #{e.backtrace.first(5).join("\n")}") if e.backtrace

      if stop_instead_of_raise?(e)
        stop_for_audio_analysis_failure!(
          message: e.message,
          details: audio_analysis_error_details(e)
        )
        return false
      end

      @essay_grading.record_grading_error!(
        stage: 'speaking_audio_analysis',
        message: e.message,
        details: { error_class: e.class.name }
      )
      raise
    end

    private

    def stop_instead_of_raise?(error)
      message = error.message.to_s

      message == MISSING_AUDIO_MESSAGE ||
        message == 'DEEPGRAM_API_KEY is missing.' ||
        message.start_with?('Audio file not found:') ||
        message.start_with?('Deepgram transcription failed:') ||
        message.start_with?('Deepgram returned invalid JSON:')
    end

    def audio_analysis_error_details(error)
      message = error.message.to_s
      details = { error_class: error.class.name }

      if message.start_with?('Deepgram transcription failed:')
        details[:error_class] = 'DeepgramHttpError'
        details[:http_status] = Regexp.last_match(1) if message =~ /HTTP (\d+)/
        details[:response_body] = message.sub(/\ADeepgram transcription failed: HTTP \d+\s*/, '').truncate(500)
      elsif message.start_with?('Deepgram returned invalid JSON:')
        details[:error_class] = 'DeepgramInvalidJson'
      elsif message.start_with?('Audio file not found:')
        details[:error_class] = 'AudioFileNotFound'
      elsif message == 'DEEPGRAM_API_KEY is missing.'
        details[:error_class] = 'MissingDeepgramApiKey'
      end

      details
    end

    def stop_for_audio_analysis_failure!(message:, details: {})
      Rails.logger.error(
        "[SpeakingEssay::AudioAnalysisService] #{message} (essay_grading #{@essay_grading.id})"
      )

      @essay_grading.record_grading_error!(
        stage: 'speaking_audio_analysis',
        message:,
        details:
      )
      @essay_grading.record_grading_failure_summary!(
        failed_steps: ['speaking_audio_analysis'],
        message:
      )
      @essay_grading.update!(status: 'stopped')

      begin
        AdminNotificationMailer.assignment_stopped_notification(@essay_grading).deliver_later
      rescue StandardError => e
        Rails.logger.error(
          "[SpeakingEssay::AudioAnalysisService] Failed to send stopped notification: #{e.message}"
        )
      end
    end

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

      assessment = raw.dig('aggregated_result', 'PronunciationAssessment') || {}
      words = raw.dig('aggregated_result', 'NBest', 0, 'Words') || []

      {
        'provider_name' => raw['provider_name'],
        'mode' => raw['mode'],
        'segment_count' => raw['segment_count'],
        'aggregate_scores' => {
          'pronunciation_score' => assessment['PronScore'],
          'accuracy_score' => assessment['AccuracyScore'],
          'fluency_score' => assessment['FluencyScore'],
          'prosody_score' => assessment['ProsodyScore'],
          'completeness_score' => assessment['CompletenessScore']
        }.compact,
        'problem_word_count' => words.count { |word| azure_problem_word?(word) }
      }
    end

    def azure_problem_word?(word)
      assessment = word['PronunciationAssessment'] || {}
      issue = assessment['ErrorType'].to_s
      raw_score = assessment['AccuracyScore']

      issue.present? && issue != 'None' ||
        (raw_score.present? && raw_score.to_f < ENV.fetch('SPEAKING_ESSAY_PROMPT_LOW_PRONUNCIATION_THRESHOLD', '70').to_f)
    end
  end
end
