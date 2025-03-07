module Schools
  # 學年更新服務
  # 負責更新現有學年
  class AcademicYearUpdater
    include ActiveModel::Model

    attr_reader :academic_year
    attr_accessor :name, :status, :start_date, :end_date

    validates :name, presence: true, if: -> { name.present? }
    validate :validate_dates, if: -> { start_date.present? || end_date.present? }

    # 初始化更新器
    # @param academic_year [SchoolAcademicYear] 現有學年
    # @param attributes [Hash] 更新屬性
    def initialize(academic_year, attributes = {})
      @academic_year = academic_year
      super(attributes)
    end

    # 執行學年更新流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      ActiveRecord::Base.transaction do
        update_academic_year
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("學年更新失敗: #{e.message}")
        false
      end
    end

    private

    # 更新學年記錄
    def update_academic_year
      # 更新名稱
      if name.present? && name != @academic_year.name
        # 檢查是否與其他學年重名
        if @academic_year.school.school_academic_years.where.not(id: @academic_year.id).exists?(name:)
          errors.add(:name, "學年名稱 #{name} 已被使用")
          raise StandardError, "學年名稱 #{name} 已被使用"
        end
        @academic_year.name = name
      end

      # 更新狀態
      @academic_year.status = status if status.present?

      # 更新日期
      if start_date.present?
        @academic_year.start_date = start_date.is_a?(Date) ? start_date : Date.parse(start_date.to_s)
      end

      if end_date.present?
        @academic_year.end_date = end_date.is_a?(Date) ? end_date : Date.parse(end_date.to_s)
      end

      # 保存更新
      @academic_year.save!
    end

    # 驗證日期
    def validate_dates
      new_start_date = if start_date.present?
                         start_date.is_a?(Date) ? start_date : Date.parse(start_date.to_s)
                       else
                         @academic_year.start_date
                       end
      new_end_date = if end_date.present?
                       end_date.is_a?(Date) ? end_date : Date.parse(end_date.to_s)
                     else
                       @academic_year.end_date
                     end

      errors.add(:base, '結束日期必須晚於開始日期') if new_end_date <= new_start_date
    rescue StandardError => e
      errors.add(:base, "日期格式錯誤: #{e.message}")
    end
  end
end
