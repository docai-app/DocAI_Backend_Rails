# frozen_string_literal: true

class CreateSmartExtractionSchemas < ActiveRecord::Migration[7.0]
  def change
    create_table :smart_extraction_schemas, id: :uuid do |t|
      t.string :name, null: false, unique: true
      t.string :description, null: true
      t.uuid :label_id, null: false, index: true, foreign_key: true
      t.jsonb :schema, default: {}
      t.jsonb :data_schema, default: {}
      t.uuid :user_id, null: false, index: true, foreign_key: true
      t.jsonb :meta, default: {}
      t.timestamps
    end
  end
end
