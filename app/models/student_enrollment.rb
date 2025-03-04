# frozen_string_literal: true

# == Schema Information
#
# Table name: student_enrollments
#
#  id                      :uuid             not null, primary key
#  general_user_id         :uuid             not null
#  school_academic_year_id :uuid             not null
#  class_name              :string
#  class_number            :string
#  status                  :integer
#  meta                    :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_student_enrollments_on_general_user_id          (general_user_id)
#  index_student_enrollments_on_school_academic_year_id  (school_academic_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (school_academic_year_id => school_academic_years.id)
#
class StudentEnrollment < ApplicationRecord
  belongs_to :general_user
  belongs_to :school_academic_year

  # 在學狀態
  enum status: {
    active: 0,        # 在讀
    graduated: 1,     # 畢業
    transferred: 2,   # 轉學
    withdrawn: 3      # 退學
  }

  # 委派學校關聯
  delegate :school, to: :school_academic_year

  # 驗證
  validates :class_name, presence: true
  validates :class_number, presence: true
  validates :general_user_id, uniqueness: {
    scope: :school_academic_year_id,
    message: '在同一學年中不能重複註冊'
  }

  # 獲取指定日期時的班級信息
  scope :at_date, lambda { |date|
    joins(:school_academic_year)
      .where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
  }
end
