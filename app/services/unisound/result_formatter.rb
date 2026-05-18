# frozen_string_literal: true

module Unisound
  module ResultFormatter
    module_function

    def format(result)
      return nil if result.blank? || result['lines'].blank?

      first_line = result['lines'][0] || {}
      sample = first_line['sample'].to_s
      user_text = first_line['usertext'].to_s
      pronunciation = first_line['score'].to_f

      words = (first_line['words'] || []).select { |word| word['type'] == 2 }
      ipa_words = []
      start_times = []
      end_times = []
      pair_accuracy_category = []
      is_letter_correct_all_words = []

      words.each do |word|
        if word['phonetic'].present?
          ipa_words << word['phonetic']
        elsif word['subwords'].present?
          ipa_words << word['subwords'].map { |sw| sw['subtext'].to_s }.join
        else
          ipa_words << ''
        end

        start_times << (word['begin'] || 0).to_s
        end_times << (word['end'] || 0).to_s

        word_score = word['score'].to_f
        is_correct = word_score >= 8 ? '1' : '0'
        pair_accuracy_category << is_correct

        if word['subwords'].present?
          word['subwords'].each do |subword|
            grapheme = subword['grapheme'].presence || subword['subtext'].to_s
            subword_score = subword['score'].to_f
            is_letter_correct = subword_score >= 8 ? '1' : '0'
            grapheme.length.times { is_letter_correct_all_words << is_letter_correct }
          end
        else
          word_text = word['text'].to_s
          is_letter_correct = word_score >= 8 ? '1' : '0'
          word_text.length.times { is_letter_correct_all_words << is_letter_correct }
        end

        is_letter_correct_all_words << ' '
      end

      real_transcript = sample.strip
      matched_transcript = user_text.strip
      real_transcripts_ipa = ipa_words.join(' ').strip
      warnings = build_warnings(result)

      # 字段与 essay-checker api/unisound/eval handleResult 完全一致（勿增删改键名）
      out = {
        'origin_data' => result,
        'real_transcript' => real_transcript.present? ? "#{real_transcript}." : '',
        'ipa_transcript' => real_transcripts_ipa.present? ? "#{real_transcripts_ipa}." : '',
        'pronunciation_accuracy' => sprintf('%.2f', pronunciation),
        'real_transcripts' => real_transcript,
        'matched_transcripts' => matched_transcript.present? ? "#{matched_transcript}." : '',
        'real_transcripts_ipa' => real_transcripts_ipa,
        'matched_transcripts_ipa' => real_transcripts_ipa.present? ? "#{real_transcripts_ipa}." : '',
        'pair_accuracy_category' => pair_accuracy_category.join(' '),
        'start_time' => start_times.join(' '),
        'end_time' => end_times.join(' '),
        'is_letter_correct_all_words' => is_letter_correct_all_words.join.strip
      }
      out['warnings'] = warnings if warnings.present?
      out
    end

    def build_warnings(result)
      lines = result['lines']
      return [] if lines.blank?

      checks = lines[0]['audiocheck']
      return [] unless checks.is_a?(Hash)

      warnings = []
      warnings << 'The service flagged the recording as too short.' if checks['too short'] == 10
      warnings << 'The service flagged the upload as empty audio.' if checks['emptyAudio'] == 10
      warnings << 'The service detected heavy background noise.' if checks['noise'] == 10
      warnings << 'The service detected low recording volume.' if checks['volume'] == 10
      warnings << 'The service detected a cut-off ending.' if checks['cut'] == 10
      warnings
    end
  end
end
