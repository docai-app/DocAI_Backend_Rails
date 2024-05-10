# frozen_string_literal: true

class AddOneTimeAndWillRunAtToScheduledTasks < ActiveRecord::Migration[7.0]
  def change
    add_column :scheduled_tasks, :one_time, :boolean, default: true
    add_column :scheduled_tasks, :will_run_at, :datetime, null: true
  end
end
