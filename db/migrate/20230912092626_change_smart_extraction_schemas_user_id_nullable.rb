class ChangeSmartExtractionSchemasUserIdNullable < ActiveRecord::Migration[7.0]
  def change
    change_column :smart_extraction_schemas, :user_id, :uuid, null: true, default: nil, index: true
  end
end
