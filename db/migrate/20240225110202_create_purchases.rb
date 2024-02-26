# frozen_string_literal: true

class CreatePurchases < ActiveRecord::Migration[7.0]
  def change
    create_table :purchases, id: :uuid do |t|
      t.references :user, polymorphic: true, null: false, type: :uuid, index: true
      t.references :marketplace_item, null: false, foreign_key: true, type: :uuid
      t.string :custom_name, null: true
      t.string :custom_description, null: true
      t.datetime :purchased_at
      t.jsonb :meta, null: true, default: {}

      t.timestamps
    end
  end
end
