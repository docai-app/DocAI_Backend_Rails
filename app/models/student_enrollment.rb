# frozen_string_literal: true

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
