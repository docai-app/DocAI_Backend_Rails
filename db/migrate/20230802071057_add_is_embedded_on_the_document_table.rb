# frozen_string_literal: true

class AddIsEmbeddedOnTheDocumentTable < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :is_embedded, :boolean, default: false
  end
end
