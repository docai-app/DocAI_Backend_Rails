# frozen_string_literal: true

class SmartExtractionSchema < ApplicationRecord
  belongs_to :user, optional: true, class_name: "User"
  belongs_to :tag, optional: true, class_name: "Tag", foreign_key: "label_id"
  has_many :document_smart_extraction_data, dependent: :destroy, class_name: "DocumentSmartExtractionData",
                                            foreign_key: "smart_extraction_schema_id"
  has_many :documents, through: :document_smart_extraction_data, class_name: "Document", foreign_key: "document_id"

  validates :name, presence: true
  validates :label_id, presence: true,
                       format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ }

  validate :schema_format
  validate :data_schema_format

  def schema_format
    unless schema.is_a?(Array)
      errors.add(:schema, "is not an array")
      return
    end

    schema.each do |s|
      unless s.is_a?(Hash) && s.keys.sort == %w[data_type key query]
        errors.add(:schema, "invalid entry: #{s.inspect}")
      end
    end
  end

  def data_schema_format
    schema_keys = schema.map { |s| s["key"] }

    # Check if data_schema is a hash and if its keys correspond to keys from the schema
    unless data_schema.is_a?(Hash) && (data_schema.keys - schema_keys).empty?
      errors.add(:data_schema, "is not in the required format")
    end
  end
end
