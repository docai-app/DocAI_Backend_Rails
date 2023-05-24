# frozen_string_literal: true

class AddFormModelToTheFormSchemas < ActiveRecord::Migration[7.0]
  def change
    add_column :form_schemas, :azure_form_model_id, :string
    add_column :form_schemas, :is_ready, :boolean, default: false, null: false, index: true
  end
end
