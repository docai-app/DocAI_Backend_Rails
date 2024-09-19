# frozen_string_literal: true

class UpdateDagIdCanBeNullOnScheduleTaskTable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :scheduled_tasks, :dag_id, true
  end
end
