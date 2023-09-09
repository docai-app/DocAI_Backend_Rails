# frozen_string_literal: true

class CreateDocumentSmartExtractionData < ActiveRecord::Migration[7.0]
  def change
    create_table :document_smart_extraction_data, id: :uuid do |t|
      t.jsonb :data
      t.uuid :document_id, null: false, foreign_key: true
      t.uuid :smart_extraction_schema_id, null: false, foreign_key: true, index: true,
                                          index: { name: 'index_smart_extraction_data_on_smart_extraction_schema_id' }
      t.timestamps
    end
  end
end
