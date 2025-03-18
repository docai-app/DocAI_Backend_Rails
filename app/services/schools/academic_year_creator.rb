# frozen_string_literal: true

module Schools
  # 學年創建服務
  # 負責為學校創建新學年
  class AcademicYearCreator
    include ActiveModel::Model
    include SchoolConstants

    attr_reader :academic_year, :school
    attr_accessor :name, :status, :start_date, :end_date,
                  :start_year, :start_month, :end_month

    validates :name, presence: true
    validate :validate_dates

    # 初始化創建器
    # @param school [School] 學校對象
    # @param attributes [Hash] 學年屬性
    def initialize(school, attributes = {})
      @school = school
      super(attributes)
    end

    # 執行學年創建流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      ActiveRecord::Base.transaction do
        create_academic_year
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("學年創建失敗: #{e.message}")
        false
      end
    end

    private

    # 創建學年記錄
    def create_academic_year
      # 檢查學年是否已存在
      existing_year = @school.school_academic_years.find_by(name:)
      if existing_year
        errors.add(:name, "學年 #{name} 已存在")
        raise StandardError, "學年 #{name} 已存在"
      end

      # 設置日期
      set_dates

      # 創建學年
      @academic_year = @school.school_academic_years.create!(
        name:,
        status: status || 'active',
        start_date: @calculated_start_date,
        end_date: @calculated_end_date
      )
    end

    # 設置開始和結束日期
    def set_dates
      if start_date.present? && end_date.present?
        @calculated_start_date = start_date.is_a?(Date) ? start_date : Date.parse(start_date.to_s)
        @calculated_end_date = end_date.is_a?(Date) ? end_date : Date.parse(end_date.to_s)
      else
        set_dates_from_components
      end
    end

    # 從年、月組件設置日期
    def set_dates_from_components
      region = @school.meta['region']
      defaults = ACADEMIC_YEAR_DEFAULTS[region] || ACADEMIC_YEAR_DEFAULTS['hk']

      # 使用提供的組件或從名稱解析
      year = start_year.presence || name.split('-').first.to_i
      month_start = start_month.presence || defaults[:start_month]
      month_end = end_month.presence || defaults[:end_month]

      @calculated_start_date = Date.new(year.to_i, month_start.to_i, 1)

      @calculated_end_date = if month_end.to_i < month_start.to_i
                               # 跨年學年
                               year_next = year.to_i + 1
                               Date.new(year_next, month_end.to_i, Date.new(year_next, month_end.to_i, -1).day)
                             else
                               # 同年學年
                               Date.new(year.to_i, month_end.to_i, Date.new(year.to_i, month_end.to_i, -1).day)
                             end
    end

    # 驗證日期
    def validate_dates
      set_dates
      errors.add(:base, '結束日期必須晚於開始日期') if @calculated_end_date <= @calculated_start_date
    rescue StandardError => e
      errors.add(:base, "日期格式錯誤: #{e.message}")
    end
  end
end
