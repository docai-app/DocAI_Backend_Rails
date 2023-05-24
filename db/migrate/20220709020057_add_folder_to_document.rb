# frozen_string_literal: true

class AddFolderToDocument < ActiveRecord::Migration[7.0]
  def change
    add_reference :documents, :folder, null: true, foreign_key: true, type: :uuid
  end
end
