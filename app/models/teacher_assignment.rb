# frozen_string_literal: true

# == Schema Information
#
# Table name: teacher_assignments
#
#  id                      :uuid             not null, primary key
#  general_user_id         :uuid             not null
#  school_academic_year_id :uuid             not null
#  department              :string
#  position                :string
#  status                  :integer
#  meta                    :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_teacher_assignments_on_general_user_id          (general_user_id)
#  index_teacher_assignments_on_school_academic_year_id  (school_academic_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (school_academic_year_id => school_academic_years.id)
#
class TeacherAssignment < ApplicationRecord
  belongs_to :general_user
  belongs_to :school_academic_year

  # 委派學校關聯
  delegate :school, to: :school_academic_year

  # 教師任教狀態
  enum status: {
    active: 0,        # 在職
    on_leave: 1,      # 請假中
    transferred: 2,   # 調職
    resigned: 3       # 離職
  }

  # 驗證
  validates :department, presence: true
  validates :position, presence: true
  validates :general_user_id, uniqueness: {
    scope: :school_academic_year_id,
    message: '在同一學年中不能重複分配'
  }

  # 獲取指定日期時的任教信息
  scope :at_date, lambda { |date|
    joins(:school_academic_year)
      .where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
  }

  # 元數據存儲（可擴展的教師特定設置）
  store_accessor :meta,
                 :teaching_subjects,     # 任教科目
                 :class_teacher_of,      # 班主任班級
                 :additional_duties      # 其他職務
end
