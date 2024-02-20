# frozen_string_literal: true

class ChangeEnergyConsumptionRecordUserId2Uuid < ActiveRecord::Migration[7.0]
  def change
    add_column :energy_consumption_records, :new_user_id, :uuid, null: false, index: true
    remove_column :energy_consumption_records, :user_id
    rename_column :energy_consumption_records, :new_user_id, :user_id
  end
end
