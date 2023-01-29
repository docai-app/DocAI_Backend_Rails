class AddFormFieldAndProjectionToTheFormSchemas < ActiveRecord::Migration[7.0]
  def change
    add_column :form_schemas, :form_fields, :jsonb, null: true, default: []
    add_column :form_schemas, :form_projection, :jsonb, null: true, default: []
    add_column :form_schemas, :can_project, :boolean, null: false, default: false
  end
end
