# frozen_string_literal: true

class AddMetaToDocumentSmartExtractionData < ActiveRecord::Migration[7.0]
  def change
    add_column :document_smart_extraction_data, :meta, :jsonb, default: {}
  end
end
