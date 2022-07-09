class CreateFormData < ActiveRecord::Migration[7.0]
  def change
    create_table :form_datum, id: :uuid do |t|
      t.uuid :document_id
      t.uuid :form_schema_id
      t.jsonb :data, default: {}
      t.timestamps
    end
    add_index :form_datum, :document_id
    add_index :form_datum, :form_schema_id
  end
end
