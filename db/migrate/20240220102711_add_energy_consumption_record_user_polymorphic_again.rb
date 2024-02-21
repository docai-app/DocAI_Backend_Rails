# frozen_string_literal: true

class AddEnergyConsumptionRecordUserPolymorphicAgain < ActiveRecord::Migration[7.0]
  def change
    remove_column :energy_consumption_records, :user_id
    remove_column :energy_consumption_records, :user_type
    add_reference :energy_consumption_records, :user, polymorphic: true, null: false, index: true, type: :uuid
  end
end
