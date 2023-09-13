class AddRetryCountToTheDocumentSmartExtractionData < ActiveRecord::Migration[7.0]
  def change
    add_column :document_smart_extraction_data, :retry_count, :integer, default: 0
  end
end
