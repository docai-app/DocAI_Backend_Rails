# frozen_string_literal: true

class CreateCommunities < ActiveRecord::Migration[7.0]
  def change

    create_table :communities, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :meta, null: false, default: {}
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.string :code, null: false
      
      t.timestamps
    end

    add_index :communities, :code, unique: true
  end
end