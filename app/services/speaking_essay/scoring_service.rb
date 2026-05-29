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
      @essay_grading.record_grading_error!(
        stage: 'speaking_scoring',
        message: e.message,
        details: { error_class: e.class.name }
      )
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
        deepgram_json: compact_json(deepgram_prompt_payload(analysis, speech_metrics)),
        speech_metrics_json: compact_json(speech_prompt_metrics(speech_metrics)),
        azure_pronunciation_json: compact_json(azure_prompt_payload(analysis, pronunciation_metrics)),
        pronunciation_metrics_json: compact_json(pronunciation_prompt_metrics(pronunciation_metrics)),
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

    def deepgram_prompt_payload(analysis, speech_metrics)
      analysis = (analysis || {}).deep_stringify_keys
      deepgram = (analysis['deepgram'] || {}).deep_stringify_keys
      transcript = (analysis['transcript'] || {}).deep_stringify_keys
      words = Array(transcript['words'].presence || deepgram['words'])

      {
        provider_name: deepgram['provider_name'] || 'deepgram',
        language_code: deepgram['language_code'],
        transcript_confidence: deepgram['confidence'] || transcript['confidence'],
        word_count: words.length,
        segment_count: Array(transcript['segments'].presence || deepgram['segments']).length,
        duration_seconds: (speech_metrics || {}).deep_stringify_keys['duration_seconds'],
        low_confidence_words: low_confidence_words(words)
      }.compact
    end

    def speech_prompt_metrics(speech_metrics)
      metrics = (speech_metrics || {}).deep_stringify_keys
      pauses = Array(metrics['pauses'])

      metrics.slice(
        'total_words',
        'duration_seconds',
        'words_per_minute',
        'filler_count',
        'filler_terms',
        'repeated_terms',
        'pause_count'
      ).merge(
        'longest_pauses' => longest_pauses(pauses),
        'omitted_pause_count' => [pauses.length - prompt_pause_limit, 0].max
      )
    end

    def azure_prompt_payload(analysis, pronunciation_metrics)
      analysis = (analysis || {}).deep_stringify_keys
      azure = (analysis['azure_pronunciation'] || {}).deep_stringify_keys
      metrics = pronunciation_prompt_metrics(pronunciation_metrics)

      {
        provider_name: azure['provider_name'] || metrics['provider_name'] || 'azure_speech',
        mode: azure['mode'],
        segment_count: azure['segment_count'],
        aggregate_scores: metrics.except('provider_name', 'word_level_feedback', 'problem_words', 'omitted_word_feedback_count'),
        problem_words: metrics['problem_words'],
        omitted_word_feedback_count: metrics['omitted_word_feedback_count']
      }.compact
    end

    def pronunciation_prompt_metrics(pronunciation_metrics)
      metrics = (pronunciation_metrics || {}).deep_stringify_keys
      word_feedback = Array(metrics['word_level_feedback'])

      metrics.slice(
        'provider_name',
        'overall_score',
        'raw_pronunciation_score',
        'accuracy_score',
        'fluency_score',
        'prosody_score',
        'completeness_score'
      ).merge(
        'problem_words' => problem_words(word_feedback),
        'omitted_word_feedback_count' => [word_feedback.length - prompt_word_feedback_limit, 0].max
      )
    end

    def low_confidence_words(words)
      threshold = ENV.fetch('SPEAKING_ESSAY_PROMPT_LOW_CONFIDENCE_THRESHOLD', '0.75').to_f

      Array(words).filter_map do |word|
        item = word.respond_to?(:deep_stringify_keys) ? word.deep_stringify_keys : {}
        confidence = item['confidence']
        next if confidence.nil? || confidence.to_f >= threshold

        {
          'word' => item['word'] || item['token'],
          'confidence' => confidence,
          'start' => item['start'],
          'end' => item['end']
        }.compact
      end.first(prompt_word_feedback_limit)
    end

    def longest_pauses(pauses)
      Array(pauses).map { |pause| pause.respond_to?(:deep_stringify_keys) ? pause.deep_stringify_keys : {} }
                   .sort_by { |pause| -pause['duration'].to_f }
                   .first(prompt_pause_limit)
    end

    def problem_words(word_feedback)
      Array(word_feedback).map { |word| word.respond_to?(:deep_stringify_keys) ? word.deep_stringify_keys : {} }
                          .select { |word| problematic_word?(word) }
                          .sort_by { |word| word['raw_score'].to_f }
                          .first(prompt_word_feedback_limit)
    end

    def problematic_word?(word)
      issue = word['issue'].to_s
      raw_score = word['raw_score']

      issue.present? && issue != 'None' ||
        (raw_score.present? && raw_score.to_f < ENV.fetch('SPEAKING_ESSAY_PROMPT_LOW_PRONUNCIATION_THRESHOLD', '70').to_f)
    end

    def prompt_word_feedback_limit
      ENV.fetch('SPEAKING_ESSAY_PROMPT_WORD_FEEDBACK_LIMIT', '30').to_i
    end

    def prompt_pause_limit
      ENV.fetch('SPEAKING_ESSAY_PROMPT_PAUSE_LIMIT', '12').to_i
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
