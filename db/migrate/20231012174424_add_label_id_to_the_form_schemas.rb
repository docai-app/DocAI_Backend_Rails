# frozen_string_literal: true

class AddLabelIdToTheFormSchemas < ActiveRecord::Migration[7.0]
  def change
    add_column :form_schemas, :label_id, :uuid, default: nil, null: true
  end
end
