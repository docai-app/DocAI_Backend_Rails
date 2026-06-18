# frozen_string_literal: true

class EssayAssignmentShare < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :owner_general_user, class_name: 'GeneralUser'
  belongs_to :shared_with_general_user, class_name: 'GeneralUser'
  belongs_to :shared_by_general_user, class_name: 'GeneralUser'
  belongs_to :school
  belongs_to :school_academic_year, optional: true

  enum status: {
    active: 0,
    revoked: 1
  }

  validates :status, presence: true
  validates :shared_with_general_user_id,
            uniqueness: { scope: :essay_assignment_id }

  validate :cannot_share_with_self
  validate :owner_matches_assignment

  before_validation :sync_owner_from_assignment, on: :create

  def revoke!
    update!(status: :revoked, revoked_at: Time.current)
  end

  def reactivate!(shared_by:)
    update!(
      status: :active,
      shared_by_general_user: shared_by,
      revoked_at: nil
    )
  end

  def teacher_json
    teacher = shared_with_general_user
    assignment = teacher.teacher_assignments.active.order(updated_at: :desc).first

    {
      id: teacher.id,
      email: teacher.email,
      nickname: teacher.nickname,
      department: assignment&.department,
      position: assignment&.position
    }
  end

  private

  def cannot_share_with_self
    return if shared_with_general_user_id.blank? || owner_general_user_id.blank?

    return unless shared_with_general_user_id == owner_general_user_id

    errors.add(:shared_with_general_user_id, 'cannot share assignment with yourself')
  end

  def owner_matches_assignment
    return if essay_assignment.blank? || owner_general_user_id.blank?

    return if essay_assignment.general_user_id == owner_general_user_id

    errors.add(:owner_general_user_id, 'must match assignment owner')
  end

  def sync_owner_from_assignment
    self.owner_general_user_id = essay_assignment&.general_user_id
  end
end
