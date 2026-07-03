# frozen_string_literal: true

module SentencePuzzleSupport
  extend ActiveSupport::Concern

  SENTENCE_PUZZLE_MAX_QUESTIONS = 10
  SENTENCE_PUZZLE_MIN_BLOCKS = 2
  SENTENCE_PUZZLE_MIN_ATTEMPTS = 1
  SENTENCE_PUZZLE_MAX_ATTEMPTS = 5

  class_methods do
    def normalize_sentence_puzzle_text(text)
      text.to_s
          .gsub(/\s+([.,!?;:])/, '\1')
          .gsub(/\s+/, ' ')
          .strip
    end

    def build_sentence_puzzle_text_from_blocks(blocks)
      normalized_blocks = Array(blocks).filter_map do |block|
        next unless block.is_a?(Hash)

        block['text'].to_s.strip.presence
      end

      normalize_sentence_puzzle_text(normalized_blocks.join(' '))
    end
  end

  private

  def assign_default_sentence_puzzle_rubric
    return unless category == 'sentence_puzzle'
    return if rubric.is_a?(Hash) && rubric.present?

    self.rubric = { 'name' => 'Sentence Puzzle' }
  end

  def validate_sentence_puzzle_configuration
    config = sentence_puzzle_config
    unless config.is_a?(Hash)
      errors.add(:meta, 'sentence_puzzle configuration is required')
      return
    end

    questions = Array(config['questions'])
    if questions.empty?
      errors.add(:meta, 'sentence_puzzle must include at least one question')
      return
    end

    if questions.size > SENTENCE_PUZZLE_MAX_QUESTIONS
      errors.add(:meta, "sentence_puzzle supports at most #{SENTENCE_PUZZLE_MAX_QUESTIONS} questions")
    end

    max_attempts = config['max_attempts_per_question']
    if max_attempts.present?
      attempts = max_attempts.to_i
      unless attempts.between?(SENTENCE_PUZZLE_MIN_ATTEMPTS, SENTENCE_PUZZLE_MAX_ATTEMPTS)
        errors.add(:meta, 'max_attempts_per_question must be between 1 and 5')
      end
    end

    if config.key?('show_answer_after_max_attempts') &&
       ![true, false].include?(config['show_answer_after_max_attempts'])
      errors.add(:meta, 'show_answer_after_max_attempts must be a boolean')
    end

    questions.each_with_index do |question, index|
      validate_sentence_puzzle_question!(question, index)
    end
  end

  def validate_sentence_puzzle_question!(question, index)
    unless question.is_a?(Hash)
      errors.add(:meta, "sentence_puzzle question #{index + 1} must be an object")
      return
    end

    correct_sentence = question['correct_sentence'].to_s.strip
    if correct_sentence.blank?
      errors.add(:meta, "sentence_puzzle question #{index + 1} requires a correct sentence")
    end

    blocks = Array(question['blocks'])
    if blocks.size < SENTENCE_PUZZLE_MIN_BLOCKS
      errors.add(:meta, "sentence_puzzle question #{index + 1} requires at least #{SENTENCE_PUZZLE_MIN_BLOCKS} blocks")
      return
    end

    blocks.each_with_index do |block, block_index|
      unless block.is_a?(Hash) && block['text'].to_s.strip.present?
        errors.add(:meta, "sentence_puzzle question #{index + 1} block #{block_index + 1} text cannot be blank")
      end
    end

    return if correct_sentence.blank?

    merged_text = self.class.build_sentence_puzzle_text_from_blocks(blocks)
    normalized_sentence = self.class.normalize_sentence_puzzle_text(correct_sentence)
    return if merged_text == normalized_sentence

    errors.add(:meta, "sentence_puzzle question #{index + 1} blocks must match the correct sentence")
  end

  def sentence_puzzle_config
    return nil unless meta.is_a?(Hash)

    meta['sentence_puzzle']
  end
end
