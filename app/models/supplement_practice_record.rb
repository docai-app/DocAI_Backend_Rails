# frozen_string_literal: true

# == Schema Information
#
# Table name: supplement_practice_records
#
#  id              :uuid             not null, primary key
#  essay_grading_id :uuid             not null
#  general_user_id :uuid             not null
#  status          :integer          default(0), not null
#  score           :decimal(10, 2)   default(0.0)
#  full_score      :decimal(10, 2)   default(0.0)
#  questions_count :integer          default(0)
#  using_time      :integer          default(0)
#  started_at      :datetime
#  submitted_at    :datetime
#  answers         :jsonb            not null
#  questions_data  :jsonb            not null
#  meta            :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class SupplementPracticeRecord < ApplicationRecord
  belongs_to :essay_grading
  belongs_to :general_user
  belongs_to :essay_assignment
  
  enum status: { draft: 0, submitted: 1 }
  
  # 验证
  # 注意：唯一性约束在数据库层面通过 partial unique index 实现
  # 这里添加应用层验证作为双重保障
  validate :ensure_single_submission_per_grading
  
  def ensure_single_submission_per_grading
    return unless submitted? # 只对 submitted 状态进行验证
    
    existing = self.class.where(
      essay_grading_id: essay_grading_id,
      general_user_id: general_user_id,
      status: :submitted
    ).where.not(id: id)
    
    if existing.exists?
      errors.add(:base, '每个作业只能提交一次练习')
    end
  end
  
  # 作用域
  scope :submitted, -> { where(status: :submitted) }
  scope :by_essay_grading, ->(essay_grading_id) { where(essay_grading_id: essay_grading_id) }
  scope :by_essay_assignment, ->(essay_assignment_id) { where(essay_assignment_id: essay_assignment_id) }
  scope :by_user, ->(user_id) { where(general_user_id: user_id) }
  
  # 方法
  def calculate_score!
    result = SupplementPracticeScoringService.new(self).calculate
    update!(
      score: result[:score],
      full_score: result[:full_score],
      questions_count: result[:questions_count]
    )
    result
  end
  
  def completion_percentage
    return 0 if full_score.zero?
    (score / full_score * 100).round(2)
  end
  
  # 检查是否有已保存的记录（草稿或已提交）
  def self.existing_record_for(essay_grading_id, general_user_id)
    where(essay_grading_id: essay_grading_id, general_user_id: general_user_id)
      .order(created_at: :desc)
      .first
  end
end
