# frozen_string_literal: true

class CreateKgLinkers < ActiveRecord::Migration[7.0]
  def change
    create_table :kg_linkers do |t|
      t.references :map_from, polymorphic: true, null: false
      t.references :map_to, polymorphic: true, null: false
      t.jsonb :meta, null: false, default: {}
      t.string :relation
      t.timestamps
    end
    add_index :kg_linkers, %w[map_from_id map_from_type], name: 'fk_map_from'
    add_index :kg_linkers, %w[map_to_id map_to_type], name: 'fk_map_to'
  end
end
