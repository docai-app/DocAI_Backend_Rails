# frozen_string_literal: true

class AssignmentReminder < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
  belongs_to :reminder_sender, class_name: 'GeneralUser', optional: true

  enum reminder_type: {
    email: 0
  }

  enum status: {
    pending: 0,
    sent: 1,
    failed: 2
  }

  validates :reminder_type, presence: true

  def assignment_student_assignment
    @assignment_student_assignment ||= AssignmentStudentAssignment.find_by(
      essay_assignment_id: essay_assignment_id,
      general_user_id: general_user_id
    )
  end
end
