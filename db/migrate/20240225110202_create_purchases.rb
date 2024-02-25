# frozen_string_literal: true

class CreatePurchases < ActiveRecord::Migration[7.0]
  def change
    create_table :purchases do |t|
      t.references :user, polymorphic: true, null: false, type: :uuid, index: true
      t.references :marketplace_item, null: false, foreign_key: true, type: :uuid
      t.datetime :purchased_at

      t.timestamps
    end
  end
end
