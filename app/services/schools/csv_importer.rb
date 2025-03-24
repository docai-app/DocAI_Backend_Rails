# frozen_string_literal: true

module Schools
  # CSV 導入服務
  # 負責從 CSV 文件批量導入學校
  class CsvImporter
    include ActiveModel::Model
    include SchoolConstants

    attr_reader :imported_count, :failed_count, :import_errors
    attr_accessor :file

    validates :file, presence: true

    # 初始化導入器
    # @param file [ActionDispatch::Http::UploadedFile] CSV 文件
    def initialize(file)
      @file = file
      @imported_count = 0
      @failed_count = 0
      @import_errors = {}
    end

    # 執行導入流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      begin
        process_csv
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("CSV 導入失敗: #{e.message}")
        false
      end
    end

    private

    # 處理 CSV 文件
    def process_csv
      require 'csv'

      csv_text = File.read(file.tempfile)
      csv = CSV.parse(csv_text, headers: true)

      csv.each_with_index do |row, index|
        process_row(row.to_h, index + 2) # +2 因為索引從0開始，還要跳過標題行
      rescue StandardError => e
        @failed_count += 1
        @import_errors[index + 2] = e.message
        Rails.logger.error("第 #{index + 2} 行導入失敗: #{e.message}")
      end
    end

    # 處理單行 CSV 數據
    # @param row_data [Hash] 行數據
    # @param row_number [Integer] 行號
    def process_row(row_data, row_number)
      # 驗證必要字段
      validate_row(row_data, row_number)

      # 創建學校
      ActiveRecord::Base.transaction do
        creator = SchoolCreator.new(format_row_data(row_data))

        if creator.execute
          @imported_count += 1
        else
          @failed_count += 1
          @import_errors[row_number] = creator.errors.full_messages.join(', ')
          raise StandardError, "學校創建失敗: #{creator.errors.full_messages.join(', ')}"
        end
      end
    end

    # 驗證行數據
    # @param row_data [Hash] 行數據
    # @param row_number [Integer] 行號
    def validate_row(row_data, _row_number)
      required_fields = %w[name code region]

      required_fields.each do |field|
        raise StandardError, "#{field} 字段不能為空" unless row_data[field].present?
      end

      # 驗證地區
      return if REGIONS.key?(row_data['region'].downcase)

      raise StandardError, "無效的地區: #{row_data['region']}"
    end

    # 格式化行數據以供創建器使用
    # @param row_data [Hash] 原始行數據
    # @return [Hash] 格式化後的數據
    def format_row_data(row_data)
      region = row_data['region'].downcase

      {
        name: row_data['name'],
        code: row_data['code'],
        status: row_data['status'] || 'active',
        address: row_data['address'],
        contact_email: row_data['contact_email'],
        contact_phone: row_data['contact_phone'],
        region:,
        timezone: row_data['timezone'] || TIMEZONE_BY_REGION[region],
        school_type: row_data['school_type'],
        curriculum_type: row_data['curriculum_type'],
        academic_system: row_data['academic_system'],
        academic_years: parse_academic_years(row_data['academic_years'], region),
        custom_settings: parse_custom_settings(row_data)
      }
    end

    # 解析學年數據
    # @param academic_years_str [String] 學年數據字符串
    # @param region [String] 地區代碼
    # @return [Array<Hash>] 學年數據數組
    def parse_academic_years(academic_years_str, region)
      return [] unless academic_years_str.present?

      begin
        # 嘗試解析 JSON 格式
        years_data = JSON.parse(academic_years_str)
        years_data = [years_data] unless years_data.is_a?(Array)

        years_data.map do |year_data|
          # 確保所有鍵都是符號形式
          year_data = year_data.transform_keys(&:to_sym)

          # 設置默認值
          defaults = ACADEMIC_YEAR_DEFAULTS[region] || ACADEMIC_YEAR_DEFAULTS['hk']

          {
            name: year_data[:name],
            status: year_data[:status] || 'active',
            start_year: year_data[:start_year] || year_data[:name].split('-').first.to_i,
            start_month: year_data[:start_month] || defaults[:start_month],
            end_month: year_data[:end_month] || defaults[:end_month]
          }
        end
      rescue JSON::ParserError
        # 如果不是 JSON 格式，解析為分號分隔的格式
        academic_years_str.split(';').map do |year_str|
          name, status = year_str.split(':')
          start_year = name.split('-').first.to_i
          defaults = ACADEMIC_YEAR_DEFAULTS[region] || ACADEMIC_YEAR_DEFAULTS['hk']

          {
            name:,
            status: status || 'active',
            start_year:,
            start_month: defaults[:start_month],
            end_month: defaults[:end_month]
          }
        end
      end
    end

    # 解析自定義設置數據
    # @param row_data [Hash] 行數據
    # @return [Hash] 自定義設置
    def parse_custom_settings(row_data)
      custom_settings = {}

      # 找出所有以 custom_ 開頭的字段
      row_data.each do |key, value|
        if key.start_with?('custom_') && value.present?
          setting_key = key.sub('custom_', '')
          custom_settings[setting_key] = value
        end
      end

      custom_settings
    end
  end
end
