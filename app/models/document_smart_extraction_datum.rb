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

  def max_retry
    3
  end

  def is_max_retry?
    retry_count >= max_retry
  end
end
