# frozen_string_literal: true

# == Schema Information
#
# Table name: schools
#
#  id            :uuid             not null, primary key
#  name          :string           not null
#  code          :string           not null
#  status        :integer          default("active")
#  address       :string
#  contact_email :string
#  contact_phone :string
#  timezone      :string
#  meta          :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_schools_on_code  (code) UNIQUE
#  index_schools_on_name  (name) UNIQUE
#
class School < ApplicationRecord
  # 關聯
  has_many :school_academic_years, dependent: :destroy
  has_many :student_enrollments, through: :school_academic_years
  has_many :teacher_assignments, through: :school_academic_years

  # 驗證
  validates :name, presence: true
  validates :code, presence: true, uniqueness: true

  # 學校狀態
  enum status: {
    active: 0,      # 正常運作
    inactive: 1,    # 暫停服務
    pending: 2      # 待啟用
  }

  # 元數據存儲（可擴展的學校特定設置）
  store_accessor :meta,
                 :school_type,           # 學校類型（小學/中學/大學）
                 :curriculum_type,       # 課程類型（本地/國際/IB等）
                 :academic_system,       # 學制（6+3+3/8+4等）
                 :custom_settings        # 自定義設置

  # 獲取當前學年
  def current_academic_year
    school_academic_years.active.first
  end

  # 根據日期獲取學年
  def academic_year_at(date)
    school_academic_years.where('start_date <= ? AND end_date >= ?', date, date).first
  end
end
