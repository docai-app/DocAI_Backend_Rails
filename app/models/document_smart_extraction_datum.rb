# frozen_string_literal: true

# == Schema Information
#
# Table name: document_smart_extraction_data
#
#  id                         :uuid             not null, primary key
#  data                       :jsonb
#  document_id                :uuid             not null
#  smart_extraction_schema_id :uuid             not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  status                     :integer          default("awaiting")
#  is_ready                   :boolean          default(FALSE)
#  retry_count                :integer          default(0)
#  meta                       :jsonb
#
class DocumentSmartExtractionDatum < ApplicationRecord
  belongs_to :document, class_name: 'Document', foreign_key: 'document_id'
  belongs_to :smart_extraction_schema
  
  enum status: %i[awaiting extracting completed retry failed]

  before_save :validate_and_cleanup_data

  def max_retry
    3
  end

  def is_max_retry?
    retry_count >= max_retry
  end

  def schema
    smart_extraction_schema.schema
  end

  def validate_and_cleanup_data
    # valid_keys = {
    #   "participant" => "string",
    #   "department" => "string",
    #   "date" => "date",
    #   "topic" => "string",
    #   "number" => "number" # 假設你也有數字類型的鍵
    # }
    valid_keys = schema.each_with_object({}) do |item, hash|
      hash[item["key"]] = item["data_type"]
    end

    # 確保 data 是一個對象
    return unless data.is_a?(Hash)

    data_changed = false

    valid_keys.each do |key, type|
      next unless data.key?(key)

      case type
      when "date"
        if valid_date?(data[key])
          data[key] = format_date(data[key])
          data_changed = true
        else
          data.delete(key)
          data_changed = true
        end
      when "string"
        unless data[key].is_a?(String)
          data.delete(key)
          data_changed = true
        end
      when "number"
        unless data[key].is_a?(Numeric)
          data.delete(key)
          data_changed = true
        end
      end
    end

    # 如果 data 有更改，则标记为已更改
    data_will_change! if data_changed
  end

  # 驗證日期是否有效
  def valid_date?(date_str)
    # 嘗試解析多種不同的日期格式
    date_formats = ["%Y年%m月%d日", "%y/%m/%d", "%y.%m.%d", "%Y.%m.%d", "%Y-%m-%d"]
    date_formats.any? do |format|
      begin
        Date.strptime(date_str, format)
        true
      rescue ArgumentError
        false
      end
    end
  end

  private 
  # 將日期格式化為 "%Y/%m/%d"
  def format_date(date_str)
    date = Date.parse(date_str)
    date.strftime("%Y/%m/%d")
  rescue ArgumentError
    nil
  end

end
