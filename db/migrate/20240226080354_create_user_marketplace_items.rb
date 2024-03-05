# frozen_string_literal: true

class CreateUserMarketplaceItems < ActiveRecord::Migration[7.0]
  def change
    create_table :user_marketplace_items, id: :uuid do |t|
      t.references :user, polymorphic: true, null: false, type: :uuid, index: true
      t.references :marketplace_item, null: false, foreign_key: true, type: :uuid, index: true
      t.string :custom_name
      t.text :custom_description
      t.references :purchase, null: false, foreign_key: true, type: :uuid
      t.jsonb :meta, default: {}, null: false

      t.timestamps
    end
  end
end
