# frozen_string_literal: true

class CreateLinks < ActiveRecord::Migration[7.0]
  def change
    create_table :links do |t|
      t.string :title
      t.string :url
      t.references :link_set, null: false, foreign_key: true
      t.jsonb :meta, default: {}, null: false

      t.timestamps
    end
  end
end
