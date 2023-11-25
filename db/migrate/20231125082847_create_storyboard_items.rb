# frozen_string_literal: true

class CreateStoryboardItems < ActiveRecord::Migration[7.0]
  def change
    create_table :storyboard_items, id: :uuid do |t|
      t.string :name, null: false
      t.text :description, null: true
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.string :query, null: false
      t.string :item_type, null: false, index: true
      t.text :data, default: ''
      t.text :sql, default: ''
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end
