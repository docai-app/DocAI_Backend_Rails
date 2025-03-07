module Schools
  # 學校創建服務
  # 負責新學校的創建邏輯
  class SchoolCreator
    include ActiveModel::Model
    include SchoolConstants

    attr_reader :school
    attr_accessor :name, :code, :status, :address,
                  :contact_email, :contact_phone,
                  :region, :timezone,
                  :school_type, :curriculum_type,
                  :academic_system,
                  :academic_years, :custom_settings

    validates :name, :code, :region, presence: true
    validates :code, format: { with: /\A[A-Z0-9_]+\z/, message: '只能包含大寫字母、數字和下劃線' }
    validate :validate_region
    validate :validate_school_type
    validate :validate_curriculum_type
    validate :validate_academic_system

    # 執行學校創建流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      ActiveRecord::Base.transaction do
        create_school
        create_academic_years
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("學校創建失敗: #{e.message}")
        false
      end
    end

    private

    # 創建學校記錄
    def create_school
      @school = School.find_or_initialize_by(code:)

      # 如果學校已存在且不是處於初始狀態，報錯
      raise StandardError, "學校代碼 #{code} 已存在" if !@school.new_record? && @school.status != 'pending'

      @school.assign_attributes(school_attributes)
      @school.save!
    end

    # 準備學校屬性
    # @return [Hash] 學校屬性
    def school_attributes
      {
        name:,
        code:,
        status: status || 'active',
        address:,
        contact_email:,
        contact_phone:,
        timezone: timezone || TIMEZONE_BY_REGION[region],
        meta: {
          region:,
          school_type:,
          curriculum_type:,
          academic_system:,
          custom_settings: custom_settings || {}
        }
      }
    end

    # 創建學年記錄
    def create_academic_years
      # 如果沒有提供學年信息，創建默認學年
      years_data = academic_years.presence || [generate_default_academic_year]

      Array(years_data).each do |year_data|
        create_single_academic_year(year_data)
      end
    end

    # 創建單個學年
    # @param year_data [Hash] 學年數據
    def create_single_academic_year(year_data)
      # 設置學年的起始和結束日期
      start_year = year_data[:start_year].to_i
      start_month = year_data[:start_month].to_i || ACADEMIC_YEAR_DEFAULTS[region][:start_month]
      end_month = year_data[:end_month].to_i || ACADEMIC_YEAR_DEFAULTS[region][:end_month]

      start_date = Date.new(start_year, start_month, 1)
      end_date = if end_month < start_month
                   Date.new(start_year + 1, end_month, Date.new(start_year + 1, end_month, -1).day)
                 else
                   Date.new(start_year, end_month, Date.new(start_year, end_month, -1).day)
                 end

      # 創建或更新學年
      academic_year = @school.school_academic_years.find_or_initialize_by(name: year_data[:name])
      academic_year.update!(
        start_date:,
        end_date:,
        status: year_data[:status] || 'active'
      )
    end

    # 生成默認學年數據
    # @return [Hash] 默認學年數據
    def generate_default_academic_year
      current_year = Date.today.year
      defaults = ACADEMIC_YEAR_DEFAULTS[region] || ACADEMIC_YEAR_DEFAULTS['hk']

      {
        name: "#{current_year}-#{current_year + 1}",
        status: 'active',
        start_year: current_year,
        start_month: defaults[:start_month],
        end_month: defaults[:end_month]
      }
    end

    # 驗證地區
    def validate_region
      return if REGIONS.key?(region)

      errors.add(:region, "無效的地區: #{region}")
    end

    # 驗證學校類型
    def validate_school_type
      return unless region.present? && school_type.present?
      return if SCHOOL_TYPES[region]&.key?(school_type)

      errors.add(:school_type, "該地區不支持的學校類型: #{school_type}")
    end

    # 驗證課程類型
    def validate_curriculum_type
      return unless region.present? && curriculum_type.present?
      return if CURRICULUM_TYPES[region]&.key?(curriculum_type)

      errors.add(:curriculum_type, "該地區不支持的課程類型: #{curriculum_type}")
    end

    # 驗證學制
    def validate_academic_system
      return unless region.present? && academic_system.present?
      return if ACADEMIC_SYSTEMS[region]&.key?(academic_system)

      errors.add(:academic_system, "該地區不支持的學制: #{academic_system}")
    end
  end
end
