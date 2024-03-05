# frozen_string_literal: true

class CreateGeneralUserFiles < ActiveRecord::Migration[7.0]
  def change
    create_table :general_user_files, id: :uuid do |t|
      t.references :general_user, null: false, foreign_key: true, type: :uuid, index: true
      t.string :file_type, null: false, index: true
      t.string :file_url
      t.integer :file_size, null: false, default: 0
      t.string :title, null: true, default: ''
      t.references :user_marketplace_item, null: true, foreign_key: true, type: :uuid
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end
