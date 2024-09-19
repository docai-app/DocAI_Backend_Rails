# frozen_string_literal: true

class ChangeScheduledTasksIdToUuid < ActiveRecord::Migration[7.0]
  def change
    remove_column :scheduled_tasks, :id
    add_column :scheduled_tasks, :id, :uuid, default: 'gen_random_uuid()', null: false, primary_key: true
  end
end
