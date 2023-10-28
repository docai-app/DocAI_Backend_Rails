# frozen_string_literal: true

class CreateChatbotsTable < ActiveRecord::Migration[7.0]
  def change
    create_table :chatbots, id: :uuid do |t|
      t.string :name
      t.string :description
      t.uuid :user_id, null: false, index: true, foreign_key: true
      t.integer :category, default: 0, null: false, index: true
      t.jsonb :meta, default: {}
      t.jsonb :source, default: {}
      t.timestamps
    end
  end
end
