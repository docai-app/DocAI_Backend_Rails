# frozen_string_literal: true

class CreateEnergies < ActiveRecord::Migration[7.0]
  def change
    create_table :energies, id: :uuid do |t|
      t.integer :value, default: 100
      t.uuid :user_id, null: false, index: true
      t.string :user_type, null: false, index: true
      t.string :entity_name, null: true, index: true

      t.timestamps
    end
  end
end
