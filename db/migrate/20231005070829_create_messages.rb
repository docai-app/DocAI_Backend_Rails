# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :messages, id: :uuid do |t|
      t.references :chatbot, null: false, foreign_key: true, type: :uuid
      t.text :content, null: false
      t.string :role, null: false, default: 'user'
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string :object_type, null: false, index: true
      t.boolean :is_read, null: false, default: false
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end
