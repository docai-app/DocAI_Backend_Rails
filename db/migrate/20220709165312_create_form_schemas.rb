# frozen_string_literal: true

class CreateFormSchemas < ActiveRecord::Migration[7.0]
  def change
    create_table :form_schemas, id: :uuid do |t|
      t.string :name
      t.json :form_schema, default: {}
      t.json :ui_schema, default: {}
      t.jsonb :data_schema, default: {}
      t.text :description, null: true, default: nil
      t.timestamps
    end
    add_index :form_schemas, :name
  end
end
