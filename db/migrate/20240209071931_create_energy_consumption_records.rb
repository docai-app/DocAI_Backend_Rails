# frozen_string_literal: true

class CreateEnergyConsumptionRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :energy_consumption_records, id: :uuid do |t|
      t.references :user, polymorphic: true, null: false
      t.uuid :marketplace_item_id, null: false, index: true, references: :marketplace_items, type: :uuid
      t.integer :energy_consumed

      t.timestamps
    end
  end
end
