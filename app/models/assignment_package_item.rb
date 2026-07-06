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
    {
      id: id,
      position: position,
      status: status,
      essay_grading_id: essay_grading_id,
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
end
