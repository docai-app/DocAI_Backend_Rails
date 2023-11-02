# frozen_string_literal: true

class AddSmartExtractionSchemasCountOnTag < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :smart_extraction_schemas_count, :integer, default: 0
  end
end

