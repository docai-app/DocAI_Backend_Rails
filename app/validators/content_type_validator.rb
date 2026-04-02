# frozen_string_literal: true

# ContentTypeValidator
#
# 自定義驗證器，用於驗證 Active Storage 附件的 content_type
# 支援多種配置選項：
# - in: 允許的 content_type 陣列
# - message: 自定義錯誤訊息
#
# 使用範例：
# validates :avatar, content_type: { in: ['image/jpeg', 'image/png'],
#                                   message: 'must be a JPEG or PNG image' }
class ContentTypeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value.respond_to?(:attached?) && value.attached?

    # 處理單個附件
    if value.respond_to?(:content_type)
      validate_content_type(record, attribute, value)
    # 處理多個附件
    elsif value.respond_to?(:each)
      value.each do |attachment|
        validate_content_type(record, attribute, attachment)
      end
    end
  end

  private

  def validate_content_type(record, attribute, attachment)
    content_type = attachment.content_type
    allowed_types = options[:in] || options[:with]

    return if allowed_types.nil? || allowed_types.include?(content_type)

    message = options[:message] || "must be one of: #{allowed_types.join(', ')}"
    record.errors.add(attribute, message)
  end
end
