# frozen_string_literal: true

class AddProjectionImageUrlToTheFormSchemas < ActiveRecord::Migration[7.0]
  def change
    add_column :form_schemas, :projection_image_url, :string, null: true, default: ''
  end
end
