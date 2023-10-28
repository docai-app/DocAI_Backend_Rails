# frozen_string_literal: true

class CreateIdentities < ActiveRecord::Migration[7.0]
  def change
    create_table :identities, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: true, index: true
      t.string :uid, null: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end
  end
end
