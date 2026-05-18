# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

module SpeakingEssay
  class AzurePronunciationAssessor
    def call(audio_path:, reference_text:)
      raise 'AZURE_SPEECH_KEY is missing.' if ENV['AZURE_SPEECH_KEY'].blank?
      raise 'AZURE_SPEECH_REGION is missing.' if ENV['AZURE_SPEECH_REGION'].blank?
      raise 'Transcript is blank; Azure pronunciation assessment requires reference text.' if reference_text.blank?

      reference_file = Tempfile.new(['speaking-reference', '.txt'])
      reference_file.write(reference_text.to_s)
      reference_file.close

      stdout, stderr, status = Open3.capture3(
        env,
        python_bin,
        script_path,
        '--audio',
        audio_path,
        '--reference',
        reference_file.path,
        '--locale',
        ENV.fetch('AZURE_SPEECH_LOCALE', 'en-US')
      )

      raise "Azure pronunciation failed: #{stderr.presence || stdout}" unless status.success?

      normalize(JSON.parse(stdout))
    rescue JSON::ParserError => e
      raise "Azure pronunciation returned invalid JSON: #{e.message}"
    ensure
      reference_file&.close
      reference_file&.unlink
    end

    private

    def env
      {
        'AZURE_SPEECH_KEY' => ENV.fetch('AZURE_SPEECH_KEY'),
        'AZURE_SPEECH_REGION' => ENV.fetch('AZURE_SPEECH_REGION'),
        'AZURE_SPEECH_LOCALE' => ENV.fetch('AZURE_SPEECH_LOCALE', 'en-US')
      }
    end

    def python_bin
      ENV.fetch('AZURE_SPEECH_PYTHON_BIN', 'python3')
    end

    def script_path
      Rails.root.join('script', 'azure_pronunciation_continuous.py').to_s
    end

    def normalize(raw)
      assessment = raw.dig('aggregated_result', 'PronunciationAssessment') || {}
      words = raw.dig('aggregated_result', 'NBest', 0, 'Words') || []

      {
        provider_name: 'azure_speech',
        overall_score: band_from_hundred(assessment['PronScore']),
        raw_pronunciation_score: assessment['PronScore'],
        accuracy_score: assessment['AccuracyScore'],
        fluency_score: assessment['FluencyScore'],
        prosody_score: assessment['ProsodyScore'],
        completeness_score: assessment['CompletenessScore'],
        word_level_feedback: words.map do |word|
          word_assessment = word['PronunciationAssessment'] || {}
          raw_score = word_assessment['AccuracyScore']

          {
            word: word['Word'] || word['DisplayText'],
            raw_score:,
            score: band_from_hundred(raw_score),
            issue: word_assessment['ErrorType'].presence || 'None'
          }
        end,
        raw_provider_payload: raw
      }
    end

    def band_from_hundred(score)
      return nil if score.nil?

      band = (score.to_f / 100.0 * 9.0 * 2).round / 2.0
      [[band, 0].max, 9].min
    end
  end
end
