# frozen_string_literal: true

class CreateEntities < ActiveRecord::Migration[7.0]
  def change
    create_table :entities, id: :uuid do |t|
      t.string :name, null: false
      t.string :description, default: ''
      t.jsonb :meta, default: {}
      t.timestamps
    end
  end
end
