# frozen_string_literal: true

class DocumentSmartExtractionDatum < ApplicationRecord
  belongs_to :document, class_name: 'Document', foreign_key: 'document_id'
  belongs_to :smart_extraction_schema, class_name: 'SmartExtractionSchema', foreign_key: 'smart_extraction_schema_id'
end
