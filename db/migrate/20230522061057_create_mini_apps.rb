# frozen_string_literal: true

class CreateMiniApps < ActiveRecord::Migration[7.0]
  def change
    create_table :mini_apps, id: :uuid do |t|
      t.string :name
      t.string :description
      t.jsonb :meta
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.references :folder, null: true, foreign_key: true, type: :uuid, index: true
      t.timestamps
    end
  end
end
