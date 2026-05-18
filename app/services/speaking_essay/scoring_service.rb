# frozen_string_literal: true

require 'json'

module SpeakingEssay
  class ScoringService
    FULL_SCORE = 9

    def initialize(essay_grading)
      @essay_grading = essay_grading
    end

    def call
      return true unless speaking_essay?

      analysis = speaking_analysis
      transcript_text = analysis.dig('transcript', 'text').presence ||
                        @essay_grading.grading['speaking_transcript'].presence ||
                        @essay_grading.essay.to_s
      raise 'Speaking essay transcript is missing before Dify scoring.' if transcript_text.blank?

      speech_metrics = analysis['speech_metrics'].presence || @essay_grading.grading['speech_metrics'] || {}
      pronunciation_metrics = analysis['pronunciation_metrics'].presence || @essay_grading.grading['pronunciation_metrics'] || {}

      dify_result = DifyScoringClient.new(api_key: dify_app_key).call(
        user: "essay_grading:#{@essay_grading.id}",
        inputs: dify_inputs(
          transcript_text:,
          analysis:,
          speech_metrics:,
          pronunciation_metrics:
        )
      )

      speaking_report = ReportNormalizer.new.call(
        report: dify_result[:speaking_report],
        speech_metrics:,
        pronunciation_metrics:,
        raw_payloads: raw_dify_payload(dify_result)
      )

      persist_report!(speaking_report)
      true
    rescue StandardError => e
      Rails.logger.error("[SpeakingEssay::ScoringService] Failed for essay_grading #{@essay_grading.id}: #{e.message}")
      Rails.logger.error("[SpeakingEssay::ScoringService] #{e.backtrace.first(5).join("\n")}") if e.backtrace
      false
    end

    private

    def speaking_essay?
      @essay_grading.category == 'speaking_essay'
    end

    def speaking_analysis
      analysis = @essay_grading.grading['speaking_analysis']
      analysis.is_a?(Hash) ? analysis.deep_stringify_keys : {}
    end

    def dify_app_key
      @essay_grading.essay_assignment&.rubric&.dig('app_key', 'speaking_scoring').presence ||
        ENV['DIFY_SPEAKING_ESSAY_SCORING_APP_KEY'].presence ||
        ENV['DIFY_SPEAKING_ESSAY_APP_KEY']
    end

    def dify_inputs(transcript_text:, analysis:, speech_metrics:, pronunciation_metrics:)
      {
        task_type: 'IELTS Speaking Part 2',
        prompt_title: @essay_grading.topic.to_s,
        cue_card: cue_card_text,
        transcript_text:,
        deepgram_json: compact_json(analysis['deepgram'] || {}),
        speech_metrics_json: compact_json(speech_metrics),
        azure_pronunciation_json: compact_json(analysis['azure_pronunciation'] || {}),
        pronunciation_metrics_json: compact_json(pronunciation_metrics),
        heuristic_scores_json: compact_json(heuristic_scores(speech_metrics, pronunciation_metrics))
      }
    end

    def cue_card_text
      @essay_grading.essay_assignment&.hints.presence ||
        @essay_grading.essay_assignment&.assignment.to_s
    end

    def compact_json(value)
      JSON.generate(value || {})
    end

    def heuristic_scores(speech_metrics, pronunciation_metrics)
      speech_metrics = (speech_metrics || {}).deep_stringify_keys
      pronunciation_metrics = (pronunciation_metrics || {}).deep_stringify_keys

      wpm = speech_metrics['words_per_minute'].to_f
      filler_count = speech_metrics['filler_count'].to_i
      pause_count = speech_metrics['pause_count'].to_i
      pronunciation = pronunciation_metrics['overall_score'].to_f

      fluency = 5.5
      fluency += 0.5 if wpm.between?(105, 145)
      fluency -= 0.5 if wpm < 90
      fluency -= [filler_count * 0.1, 1.0].min
      fluency -= [pause_count * 0.05, 0.5].min

      {
        fluency_and_coherence: clamp_band(fluency),
        lexical_resource: 6.0,
        grammatical_range_and_accuracy: 6.0,
        pronunciation: clamp_band(pronunciation.positive? ? pronunciation : 6.0)
      }
    end

    def clamp_band(value)
      rounded = (value.to_f * 2).round / 2.0
      [[rounded, 0].max, FULL_SCORE].min
    end

    def raw_dify_payload(dify_result)
      return {} unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('SPEAKING_ESSAY_STORE_RAW_PROVIDER_PAYLOADS', 'false'))

      { 'dify_scoring' => dify_result[:raw_provider_payload] }
    end

    def persist_report!(speaking_report)
      scores = (speaking_report['scores'] || {}).deep_stringify_keys
      overall_score = scores['overall_band_score']
      missing_scores = ReportNormalizer::SCORE_KEYS.select { |key| scores[key].nil? }
      if overall_score.nil? || missing_scores.present?
        raise "Dify speaking report missing required scores: #{missing_scores.join(', ')}"
      end

      next_grading = (@essay_grading.grading || {}).deep_dup
      next_grading['speaking_report'] = speaking_report
      next_grading['scores'] = scores
      next_grading['speaking_scores'] = scores
      next_grading['overall_score'] = overall_score
      next_grading['score'] = overall_score
      next_grading['full_score'] = FULL_SCORE

      @essay_grading.update!(
        score: overall_score,
        grading: next_grading
      )
    end
  end
end
