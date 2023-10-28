# frozen_string_literal: true

class AddIsClassifiedOnDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :is_classified, :boolean, default: false
  end
end
