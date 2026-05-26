# frozen_string_literal: true

module SpeakingEssay
  class ReportNormalizer
    SCORE_KEYS = %w[
      fluency_and_coherence
      lexical_resource
      grammatical_range_and_accuracy
      pronunciation
    ].freeze

    def call(report:, speech_metrics:, pronunciation_metrics:, raw_payloads: {})
      report = (report || {}).deep_stringify_keys
      score_source = (report['scores'] || report).deep_stringify_keys
      scores = normalize_scores(score_source)
      overall = round_band(score_source['overall_band_score']) || overall_score(scores)

      {
        'scores' => scores.merge('overall_band_score' => overall),
        'evidence' => normalize_evidence(report['evidence']),
        'language_analysis' => normalize_language_analysis(report['language_analysis']),
        'speech_metrics' => speech_metrics.deep_stringify_keys,
        'pronunciation_metrics' => pronunciation_metrics.deep_stringify_keys,
        'coaching' => Array(report['coaching']).map(&:to_s).reject(&:blank?).first(6)
      }.tap do |payload|
        payload['raw_provider_payloads'] = raw_payloads if raw_payloads.present?
      end
    end

    private

    def normalize_scores(scores)
      scores = (scores || {}).deep_stringify_keys

      SCORE_KEYS.to_h do |key|
        [key, round_band(scores[key])]
      end
    end

    def normalize_evidence(evidence)
      evidence = (evidence || {}).deep_stringify_keys

      SCORE_KEYS.to_h do |key|
        [key, Array(evidence[key]).map(&:to_s).reject(&:blank?).first(4)]
      end
    end

    def normalize_language_analysis(language_analysis)
      language_analysis = (language_analysis || {}).deep_stringify_keys
      feedback = Array(language_analysis['sentence_level_feedback']).filter_map do |item|
        next unless item.is_a?(Hash)

        normalized = item.deep_stringify_keys
        category = normalized['category'].to_s
        category = 'C' unless %w[A B C].include?(category)

        {
          'sentence' => normalized['sentence'].to_s,
          'feedback' => normalized['feedback'].presence || normalized['comment'].to_s,
          'category' => category
        }
      end

      language_analysis.merge(
        'sentence_level_feedback' => feedback.first(5),
        'rewrite_suggestions' => Array(language_analysis['rewrite_suggestions']).first(5),
        'topical_strengths' => Array(language_analysis['topical_strengths']).map(&:to_s).reject(&:blank?).first(5)
      )
    end

    def overall_score(scores)
      return nil if SCORE_KEYS.any? { |key| scores[key].nil? }

      average = SCORE_KEYS.sum { |key| scores[key].to_f } / SCORE_KEYS.length
      round_band(average)
    end

    def round_band(value)
      return nil if value.nil? || value.to_s.strip.blank?

      rounded = (value.to_f * 2).round / 2.0
      [[rounded, 0].max, 9].min
    end
  end
end
