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
    withdrawn: 3,     # 退學
    promoted: 4       # 升班
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

  # 學生不能同時在多個學校有活躍狀態
  validate :student_not_in_multiple_schools_when_active

  # 學生不能在同一學校有多個活躍學年
  validate :student_not_in_multiple_active_academic_years_in_same_school

  # 獲取指定日期時的班級信息
  scope :at_date, lambda { |date|
    joins(:school_academic_year)
      .where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
  }

  private

  # 驗證學生不能同時在多個學校有活躍狀態
  def student_not_in_multiple_schools_when_active
    # 只在記錄為活躍狀態時進行驗證
    return unless active?

    # 查找該學生在其他學校的活躍記錄
    other_active_enrollments = StudentEnrollment.joins(:school_academic_year)
                                                .where(general_user_id:)
                                                .where(status: :active)
                                                .where.not(id:) # 排除當前記錄
                                                .where.not(school_academic_years: { school_id: school_academic_year.school_id })

    return unless other_active_enrollments.exists?

    other_school = School.find(other_active_enrollments.first.school_academic_year.school_id)
    errors.add(:base, "學生已經在學校「#{other_school.name}」有活躍的註冊記錄")
  end

  # 驗證學生不能在同一學校有多個活躍學年
  def student_not_in_multiple_active_academic_years_in_same_school
    # 只在記錄為活躍狀態時進行驗證
    return unless active?

    # 查找該學生在同一學校的其他活躍學年記錄
    other_active_years = StudentEnrollment.joins(:school_academic_year)
                                          .where(general_user_id:)
                                          .where(status: :active)
                                          .where.not(id:) # 排除當前記錄
                                          .where(school_academic_years: { school_id: school_academic_year.school_id })

    return unless other_active_years.exists?

    other_year = other_active_years.first.school_academic_year
    errors.add(:base, "學生已經在該學校的「#{other_year.name}」學年有活躍的註冊記錄")
  end
end
