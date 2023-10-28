# frozen_string_literal: true

class AddStatusAndIsReadyToTheDocumentSmartExtractionData < ActiveRecord::Migration[7.0]
  def change
    add_column :document_smart_extraction_data, :status, :integer, default: 0, index: true
    add_column :document_smart_extraction_data, :is_ready, :boolean, default: false, index: true
  end
end
