# frozen_string_literal: true

module SpeakingEssay
  class SpeechMetricsBuilder
    FILLER_WORDS = %w[um uh er ah hmm like actually basically literally].freeze
    FILLER_PHRASES = ['you know', 'i mean', 'sort of', 'kind of'].freeze

    def call(deepgram_result:)
      words = Array(deepgram_result[:words])
      segments = Array(deepgram_result[:segments])
      tokens = words.map { |word| normalize_token(word[:token] || word[:word]) }.reject(&:blank?)
      duration = duration_seconds(words, segments)
      pauses = pauses_from_words(words)
      filler_terms = filler_terms(tokens)

      {
        total_words: words.length,
        duration_seconds: duration,
        words_per_minute: duration.positive? ? (words.length / duration * 60.0).round(1) : 0,
        filler_count: filler_terms.values.sum,
        filler_terms:,
        repeated_terms: repeated_terms(tokens),
        pause_count: pauses.length,
        pauses:,
        segments:
      }
    end

    private

    def duration_seconds(words, segments)
      last_word_end = words.filter_map { |word| numeric_value(word[:end]) }.max.to_f
      last_segment_end = segments.filter_map { |segment| numeric_value(segment[:end]) }.max.to_f

      [last_word_end, last_segment_end].max.round(2)
    end

    def pauses_from_words(words)
      threshold = ENV.fetch('SPEAKING_ESSAY_PAUSE_SECONDS', '1.0').to_f

      words.each_cons(2).filter_map do |previous_word, current_word|
        previous_end = numeric_value(previous_word[:end])
        current_start = numeric_value(current_word[:start])
        next if previous_end.nil? || current_start.nil?

        gap = current_start - previous_end
        next if gap < threshold

        {
          start: previous_end.round(2),
          end: current_start.round(2),
          duration: gap.round(2)
        }
      end
    end

    def filler_terms(tokens)
      counts = tokens.tally.select { |token, _count| FILLER_WORDS.include?(token) }

      FILLER_PHRASES.each do |phrase|
        parts = phrase.split
        phrase_count = tokens.each_cons(parts.length).count { |slice| slice == parts }
        counts[phrase] = phrase_count if phrase_count.positive?
      end

      counts
    end

    def repeated_terms(tokens)
      tokens.each_cons(2).filter_map { |previous_token, current_token| previous_token if previous_token == current_token }
            .tally
    end

    def normalize_token(value)
      value.to_s.downcase.gsub(/\A[^\w']+|[^\w']+\z/, '')
    end

    def numeric_value(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
