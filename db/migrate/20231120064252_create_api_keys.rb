# frozen_string_literal: true

class CreateApiKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :api_keys, id: :uuid do |t|
      t.references :user, foreign_key: true, type: :uuid
      t.string :key, null: false, index: { unique: true }
      t.datetime :expires_at, null: true
      t.boolean :active, default: true
      t.string :tenant, null: false, index: true
      t.string :name, null: true, default: nil
      t.string :description, null: true, default: nil

      t.timestamps
    end
  end
end
