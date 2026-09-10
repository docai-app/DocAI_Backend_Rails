# frozen_string_literal: true

require 'uri'

# Private server-owned copy. Never nest this association in assignment JSON.
# Only a trusted QG fetch service may populate it, not assignment parameters.
class ListeningAssignmentSnapshot < ApplicationRecord
  belongs_to :essay_assignment
  validates :qg_version_id, :plain_transcript, :audio_url, :audio_metadata, presence: true
  validates :content_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :level, inclusion: { in: %w[A2 B2 C2] }
  validates :essay_assignment_id, uniqueness: true
  validate :valid_private_content
  validate :immutable_after_creation, on: :update

  def score(responses)
    ListeningSnapshotScorer.call(quiz: quiz, responses: responses)
  end

  # Explicit allowlist, rather than removing a few known answer fields.
  # Audio authorization and playback-count enforcement belong to the playback
  # endpoint; raw storage URLs are deliberately not part of this projection.
  def student_content
    {
      'version_id' => qg_version_id, 'level' => level,
      'title' => quiz['title'], 'instruction' => quiz['instruction'],
      'full_score' => quiz['full_score'],
      'questions' => quiz.fetch('questions').fetch('multiple_choice').map do |row|
        row.slice('id', 'type', 'question', 'options')
      end
    }.deep_dup
  end

  private

  def immutable_after_creation
    errors.add(:base, 'Listening snapshots cannot be changed; create a new assignment') if changed?
  end

  def valid_private_content
    errors.add(:essay_assignment, 'must be a listening assignment') unless essay_assignment&.category == 'listening'
    errors.add(:level, 'must match quiz') unless quiz.is_a?(Hash) && quiz['level'] == level
    ListeningSnapshotScorer.call(quiz: quiz, responses: [])
    uri = URI.parse(audio_url.to_s)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment
      errors.add(:audio_url, 'must be a stable HTTPS URL')
    end
  rescue ListeningSnapshotScorer::InvalidQuiz
    errors.add(:quiz, 'is not a supported listening quiz')
  rescue URI::InvalidURIError
    errors.add(:audio_url, 'is invalid')
  end
end
