# frozen_string_literal: true

class AssignmentStudentAssignment < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
  belongs_to :assignment_distribution

  enum status: {
    assigned: 0,    # 已分配，未完成
    completed: 1,   # 已完成
    overdue: 2      # 已逾期
  }

  validates :essay_assignment_id, uniqueness: { 
    scope: :general_user_id,
    message: '該作業已經分配給該學生'
  }

  before_save :update_status_based_on_submission
  after_create :check_and_update_overdue_status

  # 檢查是否有對應的 EssayGrading 記錄
  def has_submission?
    essay_grading.present? && essay_grading.status != 'draft'
  end

  def essay_grading
    @essay_grading ||= EssayGrading.find_by(
      essay_assignment_id: essay_assignment_id,
      general_user_id: general_user_id
    )
  end

  # 更新狀態基於提交情況
  def update_status_based_on_submission
    if has_submission?
      self.status = :completed
      self.completed_at ||= essay_grading.created_at
    elsif deadline.present? && deadline < Time.current && status != :completed
      self.status = :overdue
    end
  end

  # 檢查並更新逾期狀態
  def check_and_update_overdue_status
    return unless deadline.present?
    return if status == :completed

    if deadline < Time.current && !has_submission?
      update_columns(status: AssignmentStudentAssignment.statuses[:overdue])
    end
  end

  # 計算剩餘天數
  def days_remaining
    return nil unless deadline.present?
    
    days = ((deadline - Time.current) / 1.day).ceil
    days.positive? ? days : 0
  end

  # 是否逾期
  def overdue?
    return false unless deadline.present?
    deadline < Time.current && !has_submission?
  end
end
