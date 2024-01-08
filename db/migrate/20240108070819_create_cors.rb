# frozen_string_literal: true

class CreateCors < ActiveRecord::Migration[7.0]
  def change
    create_table :cors, id: :uuid do |t|
      t.string :name, null: false
      t.string :description, default: ''
      t.string :url, null: false
      t.jsonb :meta, default: {}
      t.timestamps
    end
  end
end
