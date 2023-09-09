# frozen_string_literal: true

class SmartExtractionSchema < ApplicationRecord
  belongs_to :user
  belongs_to :labels
  has_many :document_smart_extraction_data, dependent: :destroy, class_name: 'DocumentSmartExtractionData',
                                            foreign_key: 'smart_extraction_schema_id'
  has_many :documents, through: :document_smart_extraction_data, class_name: 'Document', foreign_key: 'document_id'
end
