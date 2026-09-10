# frozen_string_literal: true

module TrustedListeningGrading
  extend ActiveSupport::Concern

  included do
    before_validation :prepare_trusted_listening_result, if: :is_listening?
  end

  # Result pages need the immutable question wording, not just answer labels.
  # Keep private answers, evidence, transcript and storage URL out of this view.
  def listening_grading_for_display
    return grading unless is_listening?
    snapshot = essay_assignment&.listening_assignment_snapshot
    return grading unless snapshot

    result = grading.deep_dup
    block = result['listening'] ||= {}
    responses = Array(block['questions']).index_by { |row| row['id'].to_s }
    block['questions'] = snapshot.student_content.fetch('questions').map do |question|
      response = responses[question['id'].to_s] || {}
      question.merge(response.slice('user_answer', 'is_correct', 'score'))
    end
    block['questions_count'] = block['questions'].size
    result
  end

  def prepare_trusted_listening_result
    if persisted? && (receipt = attribute_in_database('meta')&.dig('listening_create_request'))
      self.meta = (meta || {}).merge('listening_create_request' => receipt)
    end
    snapshot = essay_assignment&.listening_assignment_snapshot
    unless snapshot
      errors.add(:base, 'Listening assignment has no trusted snapshot; recreate it from a published version')
      return
    end
    block = grading.is_a?(Hash) && grading['listening']
    responses = block.is_a?(Hash) ? block.fetch('questions', []) : []
    result = snapshot.score(responses)
    result['version_id'] = snapshot.qg_version_id
    result['level'] = snapshot.level
    if status == 'draft'
      result['questions'] = result['questions'].map { |row| row.slice('id', 'user_answer') }
      result.delete('score')
      result.delete('percentage')
      self[:score] = nil
    else
      # Capture the cumulative authorized plays for this student/assignment at
      # submission. Later edits must not replace it with client data or replay counts.
      was_submitted = persisted? && attribute_in_database('status') == 'graded'
      previous_count = attribute_in_database('grading')&.dig('listening', 'play_count') if persisted?
      result['play_count'] = if was_submitted
                               previous_count
                             else
                               ListeningPlaybackState.find_by(essay_assignment_id: essay_assignment_id,
                                 general_user_id: general_user_id)&.play_count || 0
                             end
      self[:score] = result['score']
      self.status = 'graded'
    end
    self.grading = { 'listening' => result }
  rescue ListeningSnapshotScorer::InvalidQuiz, ListeningSnapshotScorer::InvalidSubmission => error
    errors.add(:base, error.message)
  end
end
