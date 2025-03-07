module Schools
  # 學校更新服務
  # 負責現有學校的更新邏輯
  class SchoolUpdater
    include ActiveModel::Model
    include SchoolConstants

    attr_reader :school
    attr_accessor :name, :status, :address,
                  :contact_email, :contact_phone,
                  :timezone, :region,
                  :school_type, :curriculum_type,
                  :academic_system,
                  :custom_settings

    validates :name, presence: true
    validate :validate_region, if: -> { region.present? }
    validate :validate_school_type, if: -> { school_type.present? }
    validate :validate_curriculum_type, if: -> { curriculum_type.present? }
    validate :validate_academic_system, if: -> { academic_system.present? }

    # 初始化更新器
    # @param school [School] 現有學校實例
    # @param attributes [Hash] 更新屬性
    def initialize(school, attributes = {})
      @school = school
      super(attributes)
    end

    # 執行學校更新流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      ActiveRecord::Base.transaction do
        update_school
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("學校更新失敗: #{e.message}")
        false
      end
    end

    private

    # 更新學校記錄
    def update_school
      # 更新基本信息
      @school.name = name if name.present?
      @school.status = status if status.present?
      @school.address = address if address.present?
      @school.contact_email = contact_email if contact_email.present?
      @school.contact_phone = contact_phone if contact_phone.present?
      @school.timezone = timezone if timezone.present?

      # 更新元數據
      meta = @school.meta || {}
      meta['region'] = region if region.present?
      meta['school_type'] = school_type if school_type.present?
      meta['curriculum_type'] = curriculum_type if curriculum_type.present?
      meta['academic_system'] = academic_system if academic_system.present?
      meta['custom_settings'] = custom_settings if custom_settings.present?

      @school.meta = meta
      @school.save!
    end

    # 驗證地區
    def validate_region
      return if REGIONS.key?(region)

      errors.add(:region, "無效的地區: #{region}")
    end

    # 驗證學校類型
    def validate_school_type
      region_key = region.presence || @school.meta['region']
      return unless region_key.present?
      return if SCHOOL_TYPES[region_key]&.key?(school_type)

      errors.add(:school_type, "該地區不支持的學校類型: #{school_type}")
    end

    # 驗證課程類型
    def validate_curriculum_type
      region_key = region.presence || @school.meta['region']
      return unless region_key.present?
      return if CURRICULUM_TYPES[region_key]&.key?(curriculum_type)

      errors.add(:curriculum_type, "該地區不支持的課程類型: #{curriculum_type}")
    end

    # 驗證學制
    def validate_academic_system
      region_key = region.presence || @school.meta['region']
      return unless region_key.present?
      return if ACADEMIC_SYSTEMS[region_key]&.key?(academic_system)

      errors.add(:academic_system, "該地區不支持的學制: #{academic_system}")
    end
  end
end
