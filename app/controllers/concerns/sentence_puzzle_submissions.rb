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
    score = normalized_attempt['score']
    total = normalized_attempt['total']

    essay_grading.meta ||= {}
    essay_grading.meta['sentence_puzzle_attempt'] = normalized_attempt
    essay_grading.status = :graded
    essay_grading.score = score if score.present?
    essay_grading.grading ||= {}
    essay_grading.grading['sentence_puzzle'] = {
      'status' => normalized_attempt['status'].presence || 'submitted',
      'score' => score,
      'total' => total
    }
  end
end
