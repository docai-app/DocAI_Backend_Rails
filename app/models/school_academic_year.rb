# frozen_string_literal: true

# == Schema Information
#
# Table name: school_academic_years
#
#  id         :uuid             not null, primary key
#  school_id  :uuid             not null
#  name       :string           not null
#  start_date :date             not null
#  end_date   :date             not null
#  status     :integer          default("preparing")
#  meta       :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_school_academic_years_on_school_id  (school_id)
#
# Foreign Keys
#
#  fk_rails_...  (school_id => schools.id)
#
class SchoolAcademicYear < ApplicationRecord
  belongs_to :school, optional: true
  has_many :student_enrollments, dependent: :restrict_with_error
  has_many :teacher_assignments, dependent: :restrict_with_error
  has_many :teachers, through: :teacher_assignments, source: :general_user

  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date
  validate :no_overlapping_academic_years

  enum status: {
    preparing: 0,   # 準備中
    active: 1,      # 當前學年
    archived: 2     # 已歸檔
  }

  private

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?

    errors.add(:end_date, '必須在開始日期之後') if end_date < start_date
  end

  def no_overlapping_academic_years
    return if start_date.blank? || end_date.blank?

    overlapping = school.school_academic_years
                        .where.not(id:)
                        .where('start_date <= ? AND end_date >= ?', end_date, start_date)

    errors.add(:base, '學年時間範圍不能重疊') if overlapping.exists?
  end
end
