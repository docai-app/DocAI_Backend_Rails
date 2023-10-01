class ChangeLabelIdNullableOnSmartExtractionSchema < ActiveRecord::Migration[7.0]
  def change
    change_column :smart_extraction_schemas, :label_id, :uuid, null: true, default: nil, index: true
    add_column :smart_extraction_schemas, :has_label, :boolean, default: false, null: false, index: true
  end
end
