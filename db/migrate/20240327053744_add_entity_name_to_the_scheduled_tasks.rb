# frozen_string_literal: true

class AddEntityNameToTheScheduledTasks < ActiveRecord::Migration[7.0]
  def change
    add_reference :scheduled_tasks, :entity, type: :uuid, index: true
  end
end
