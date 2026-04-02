# frozen_string_literal: true

# SizeValidator
#
# 自定義驗證器，用於驗證 Active Storage 附件的文件大小
# 支援多種配置選項：
# - less_than: 文件大小必須小於指定值
# - greater_than: 文件大小必須大於指定值
# - between: 文件大小必須在指定範圍內
# - message: 自定義錯誤訊息
#
# 使用範例：
# validates :avatar, size: { less_than: 10.megabytes,
#                           message: 'must be less than 10MB' }
class SizeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value.respond_to?(:attached?) && value.attached?

    # 處理單個附件
    if value.respond_to?(:byte_size)
      validate_size(record, attribute, value)
    # 處理多個附件
    elsif value.respond_to?(:each)
      value.each do |attachment|
        validate_size(record, attribute, attachment)
      end
    end
  end

  private

  def validate_size(record, attribute, attachment)
    size = attachment.byte_size

    # 檢查 less_than 條件
    if options[:less_than] && size >= options[:less_than]
      message = options[:message] || "must be less than #{human_size(options[:less_than])}"
      record.errors.add(attribute, message)
      return
    end

    # 檢查 greater_than 條件
    if options[:greater_than] && size <= options[:greater_than]
      message = options[:message] || "must be greater than #{human_size(options[:greater_than])}"
      record.errors.add(attribute, message)
      return
    end

    # 檢查 between 條件
    return unless options[:between] && !options[:between].include?(size)

    min = human_size(options[:between].first)
    max = human_size(options[:between].last)
    message = options[:message] || "must be between #{min} and #{max}"
    record.errors.add(attribute, message)
  end

  def human_size(size)
    return "#{size} bytes" if size < 1.kilobyte

    units = %w[bytes KB MB GB TB]
    unit_index = 0
    size_float = size.to_f

    while size_float >= 1024 && unit_index < units.length - 1
      size_float /= 1024
      unit_index += 1
    end

    "#{size_float.round(1)} #{units[unit_index]}"
  end
end
