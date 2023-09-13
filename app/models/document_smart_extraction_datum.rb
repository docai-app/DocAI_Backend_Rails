# frozen_string_literal: true

class DocumentSmartExtractionDatum < ApplicationRecord
  belongs_to :document, class_name: "Document", foreign_key: "document_id"
  belongs_to :smart_extraction_schema

  enum status: %i[awaiting extracting completed retry failed]

  def max_retry
    3
  end

  def is_max_retry?
    retry_count >= max_retry
  end
end
