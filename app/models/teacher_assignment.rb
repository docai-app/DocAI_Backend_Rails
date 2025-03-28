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
    resigned: 1,      # 離職
    transferred: 2,   # 調職
    sabbatical: 3     # 休假
  }

  # 驗證
  validates :department, presence: true
  validates :position, presence: true
  validates :general_user_id, uniqueness: {
    scope: :school_academic_year_id,
    message: '在同一學年中不能重複任教'
  }

  # 教師不能同時在多個學校有活躍狀態
  validate :teacher_not_in_multiple_schools_when_active

  # 教師不能在同一學校有多個活躍學年
  validate :teacher_not_in_multiple_active_academic_years_in_same_school

  # 獲取指定日期時的任教信息
  scope :at_date, lambda { |date|
    joins(:school_academic_year)
      .where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
  }

  # 教授特定科目的教師
  scope :teaching_subject, lambda { |subject|
    where("meta->>'teaching_subjects' LIKE ?", "%#{subject}%")
  }

  # 班主任
  scope :class_teachers, -> { where("meta->>'class_teacher_of' IS NOT NULL") }

  # 元數據存儲（可擴展的教師特定設置）
  store_accessor :meta,
                 :teaching_subjects,     # 任教科目
                 :class_teacher_of,      # 班主任班級
                 :additional_duties      # 其他職務

  private

  # 驗證教師不能同時在多個學校有活躍狀態
  def teacher_not_in_multiple_schools_when_active
    # 只在記錄為活躍狀態時進行驗證
    return unless active?

    # 查找該教師在其他學校的活躍記錄
    other_active_assignments = TeacherAssignment.joins(:school_academic_year)
                                                .where(general_user_id:)
                                                .where(status: :active)
                                                .where.not(id:) # 排除當前記錄
                                                .where.not(school_academic_years: { school_id: school_academic_year.school_id })

    return unless other_active_assignments.exists?

    other_school = School.find(other_active_assignments.first.school_academic_year.school_id)
    errors.add(:base, "教師已經在學校「#{other_school.name}」有活躍的任教記錄")
  end

  # 驗證教師不能在同一學校有多個活躍學年
  def teacher_not_in_multiple_active_academic_years_in_same_school
    # 只在記錄為活躍狀態時進行驗證
    return unless active?

    # 查找該教師在同一學校的其他活躍學年記錄
    other_active_years = TeacherAssignment.joins(:school_academic_year)
                                          .where(general_user_id:)
                                          .where(status: :active)
                                          .where.not(id:) # 排除當前記錄
                                          .where(school_academic_years: { school_id: school_academic_year.school_id })

    return unless other_active_years.exists?

    other_year = other_active_years.first.school_academic_year
    errors.add(:base, "教師已經在該學校的「#{other_year.name}」學年有活躍的任教記錄")
  end
end
