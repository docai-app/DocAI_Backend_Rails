# frozen_string_literal: true

# == Schema Information
#
# Table name: smart_extraction_schemas
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :string
#  label_id    :uuid
#  schema      :jsonb
#  data_schema :jsonb
#  user_id     :uuid
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  has_label   :boolean          default(FALSE), not null
#
class SmartExtractionSchema < ApplicationRecord
  belongs_to :user, optional: true, class_name: 'User'
  belongs_to :tag, optional: true, class_name: 'Tag', foreign_key: 'label_id', counter_cache: true
  has_many :document_smart_extraction_datum, dependent: :destroy, class_name: 'DocumentSmartExtractionDatum',
                                             foreign_key: 'smart_extraction_schema_id'
  has_many :documents, through: :document_smart_extraction_datum, class_name: 'Document', foreign_key: 'document_id'

  validates :name, presence: true
  validate :schema_format
  validate :data_schema_format

  def schema_format
    unless schema.is_a?(Array)
      errors.add(:schema, 'is not an array')
      return
    end

    # 檢查query的類型是否一致
    first_query_type = nil

    schema.each do |s|
      # 確保每個entry包含這三個鍵
      puts s
      unless s.keys.sort == %w[key data_type query].sort
        errors.add(:schema, "invalid entry: #{s.inspect}")
        next
      end

      # 確認query類型
      query = s['query']
      current_query_type = query.is_a?(Array) ? :array : :string

      # 設置或檢查query類型是否一致
      if first_query_type.nil?
        first_query_type = current_query_type # 記錄第一個query的類型
      elsif current_query_type != first_query_type
        errors.add(:schema, 'All query fields should be of the same type')
        break # 如果類型不一致，中斷檢查
      end
    end
  end

  def data_schema_format
    schema_keys = schema.map { |s| s['key'] }

    # Check if data_schema is a hash and if its keys same to keys from the schema
    # return if data_schema.is_a?(Hash) && (data_schema.keys - schema_keys).empty?
    return if data_schema.is_a?(Hash) && (data_schema.keys.sort == schema_keys.sort) && schema_keys.all? do |key|
      key.match?(/\A[a-z_]+\z/)
    end

    errors.add(:data_schema, 'is not in the required format')
  end

  def create_smart_extraction_schema_view
    getSubdomain = Apartment::Tenant.current
    selectString = data_schema.map { |row| "data->>'#{row[0]}' AS #{row[0]}" }.join(', ')
    sql = "CREATE VIEW \"#{getSubdomain}\".\"smart_extraction_schema_#{id}\" AS SELECT #{selectString}, meta->>'document_uploaded_at' AS uploaded_at FROM \"#{getSubdomain}\".document_smart_extraction_data WHERE smart_extraction_schema_id = '#{id}';"
    ActiveRecord::Base.connection.execute(sql)
    true
  rescue StandardError => e
    puts e.message
    false
  end

  def drop_smart_extraction_schema_view
    getSubdomain = Apartment::Tenant.current
    sql = "DROP VIEW IF EXISTS \"#{getSubdomain}\".\"smart_extraction_schema_#{id}\";"
    ActiveRecord::Base.connection.execute(sql)
    true
  rescue StandardError => e
    puts e.message
    false
  end

  def as_json(options = {})
    super(options.merge(
      include: {
        tag: { only: %i[id name] },
        user: { only: %i[id nickname email] }
      }
    )).transform_keys do |key|
      case key
      when 'tag'
        'label'
      else
        key
      end
    end
  end
end
