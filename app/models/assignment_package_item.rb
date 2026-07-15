# frozen_string_literal: true

class AssignmentPackageItem < ApplicationRecord
  enum status: { locked: 0, available: 1, completed: 2, skipped: 3 }

  belongs_to :assignment_package
  belongs_to :essay_assignment
  belongs_to :essay_grading, optional: true

  validates :position, presence: true
  validates :position, uniqueness: { scope: :assignment_package_id }
  validates :essay_assignment_id, uniqueness: { scope: :assignment_package_id }

  def as_json_for_package
    assignment = essay_assignment
    grading = display_grading
    score_snapshot =
      if grading
        AssignmentPackages::GradingScoreSnapshot.for(
          grading,
          category: category.presence || assignment.category
        )
      end

    {
      id: id,
      position: position,
      status: status,
      essay_grading_id: grading&.id,
      essay_grading_status: grading&.status,
      essay_grading_score: score_snapshot&.dig(:score),
      essay_grading_full_score: score_snapshot&.dig(:full_score),
      essay_grading_score_label: score_snapshot&.dig(:score_label),
      unlocked_at: unlocked_at,
      completed_at: completed_at,
      title: title.presence || assignment.title,
      category: category.presence || assignment.category,
      locked: locked?,
      can_start: available? || completed?,
      meta: meta,
      essay_assignment: {
        id: assignment.id,
        title: assignment.title,
        topic: assignment.topic,
        category: assignment.category,
        code: assignment.code,
        assignment: assignment.assignment
      },
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def display_grading
    resolve_grading_for_display
  end

  private

  def resolve_grading_for_display
    return essay_grading if essay_grading.present?

    owner_id = assignment_package.general_user_id
    return nil unless owner_id

    essay_assignment.essay_gradings
                    .where(general_user_id: owner_id)
                    .order(updated_at: :desc)
                    .first
  end
end
