# frozen_string_literal: true

module SentencePuzzleSubmissions
  extend ActiveSupport::Concern

  private

  def sentence_puzzle_assignment?(assignment)
    assignment&.category == 'sentence_puzzle'
  end

  def sentence_puzzle_submission_request?(assignment, grading_params)
    sentence_puzzle_assignment?(assignment) &&
      sentence_puzzle_attempt_payload(grading_params).present?
  end

  def sentence_puzzle_attempt_payload(grading_params)
    meta = grading_params[:meta]
    return nil unless meta.is_a?(Hash) || meta.is_a?(ActionController::Parameters)

    attempt = meta[:sentence_puzzle_attempt] || meta['sentence_puzzle_attempt']
    attempt.is_a?(Hash) || attempt.is_a?(ActionController::Parameters) ? attempt.to_h : nil
  end

  def apply_sentence_puzzle_submission!(essay_grading, grading_params)
    attempt = sentence_puzzle_attempt_payload(grading_params)
    return unless attempt.is_a?(Hash)

    normalized_attempt = attempt.deep_stringify_keys
    is_draft = grading_params[:status].to_s == 'draft' || normalized_attempt['status'].to_s == 'draft'
    normalized_attempt['status'] = is_draft ? 'draft' : 'submitted'
    normalized_attempt = verified_sentence_puzzle_attempt(essay_grading.essay_assignment, normalized_attempt) unless is_draft
    score = normalized_attempt['score']
    total = normalized_attempt['total']

    essay_grading.meta ||= {}
    essay_grading.meta['sentence_puzzle_attempt'] = normalized_attempt
    essay_grading.status = is_draft ? :draft : :graded
    essay_grading.score = score if score.present?
    essay_grading.grading ||= {}
    essay_grading.grading['sentence_puzzle'] = {
      'status' => normalized_attempt['status'].presence || 'submitted',
      'score' => score,
      'total' => total
    }
  end

  def verified_sentence_puzzle_attempt(assignment, attempt)
    config = assignment.meta.is_a?(Hash) ? assignment.meta.deep_stringify_keys['sentence_puzzle'] : nil
    questions = Array(config&.dig('questions')).filter_map do |question|
      question.deep_stringify_keys if question.is_a?(Hash)
    end
    answers_by_question_id = Array(attempt['answers']).filter_map do |answer|
      next unless answer.is_a?(Hash)

      normalized_answer = answer.deep_stringify_keys
      [normalized_answer['question_id'].to_s, normalized_answer]
    end.to_h
    max_attempts = config&.dig('max_attempts_per_question').to_i.clamp(1, 5)

    verified_answers = questions.map.with_index(1) do |question, index|
      answer = answers_by_question_id[question['id'].to_s] || {}
      blocks = Array(question['blocks']).filter_map do |block|
        block.deep_stringify_keys if block.is_a?(Hash)
      end
      blocks_by_id = blocks.index_by { |block| block['id'].to_s }
      selected_ids = Array(answer['student_block_order']).map(&:to_s)
      valid_selection = selected_ids.length == blocks.length &&
                        selected_ids.uniq.length == blocks.length &&
                        selected_ids.all? { |block_id| blocks_by_id.key?(block_id) }
      student_sentence = if valid_selection
                           selected_ids.map { |block_id| blocks_by_id.fetch(block_id)['text'].to_s }.join(' ')
                         else
                           ''
                         end
      correct_sentence = question['correct_sentence'].to_s

      {
        'question_id' => question['id'].to_s,
        'question_order' => question['order'].presence || index,
        'correct_sentence' => correct_sentence,
        'attempts_used' => answer['attempts_used'].to_i.clamp(0, max_attempts),
        'is_correct' => valid_selection &&
                        normalize_sentence_puzzle_text(student_sentence) ==
                          normalize_sentence_puzzle_text(correct_sentence),
        'student_block_order' => valid_selection ? selected_ids : [],
        'student_sentence' => valid_selection ? normalize_sentence_puzzle_text(student_sentence) : '',
        'revealed_answer' => ActiveModel::Type::Boolean.new.cast(answer['revealed_answer']),
        'answered_at' => answer['answered_at'].presence
      }
    end

    attempt.merge(
      'status' => 'submitted',
      'score' => verified_answers.count { |answer| answer['is_correct'] },
      'total' => questions.length,
      'answers' => verified_answers
    ).except('progress')
  end

  def normalize_sentence_puzzle_text(text)
    text.to_s.gsub(/\s+([.,!?;:])/, '\\1').squish
  end
end
