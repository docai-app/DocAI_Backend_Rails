# frozen_string_literal: true

class AddUploadStatusToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :upload_local_path, :string
    add_index :documents, :upload_local_path
  end
end
