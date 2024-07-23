# frozen_string_literal: true

class CreateScheduledTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :scheduled_tasks do |t|
      t.string :name
      t.string :description
      t.references :user, null: false, type: :uuid, polymorphic: true, index: true
      t.references :dag, null: false, type: :uuid, index: true
      t.string :cron
      t.integer :status, default: 0
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end
