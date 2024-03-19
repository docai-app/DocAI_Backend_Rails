# frozen_string_literal: true

class CreateGeneralUserFeeds < ActiveRecord::Migration[7.0]
  def change
    create_table :general_user_feeds, id: :uuid do |t|
      t.references :general_user, null: false, foreign_key: true, type: :uuid, index: true
      t.string :title, null: true, default: ''
      t.string :description, null: true, default: ''
      t.string :cover_image, null: true, default: ''
      t.string :file_type, null: false, index: true
      t.string :file_url, null: true, default: ''
      t.integer :file_size, null: true, default: 0
      t.references :user_marketplace_item, null: true, foreign_key: true, type: :uuid
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end
