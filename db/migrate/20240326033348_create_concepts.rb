# frozen_string_literal: true

class CreateConcepts < ActiveRecord::Migration[7.0]
  def change
    create_table :concepts do |t|
      t.string :source
      t.string :name
      t.uuid :root_node
      t.jsonb :meta, null: false, default: {}
      t.integer :sort

      t.timestamps
    end
    add_index :concepts, :root_node
  end
end
