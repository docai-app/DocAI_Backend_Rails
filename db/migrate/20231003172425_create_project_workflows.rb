# frozen_string_literal: true

class CreateProjectWorkflows < ActiveRecord::Migration[7.0]
  def change
    create_table :project_workflows, id: :uuid do |t|
      t.string :name, null: false
      t.integer :status, default: 0, null: false
      t.string :description
      t.uuid :used_id, null: true
      t.boolean :is_process_workflow, default: false
      t.datetime :deadline, null: true
      t.jsonb :meta, default: {}
      t.timestamps
    end
    add_index :project_workflows, :status
    add_index :project_workflows, :is_process_workflow
  end
end
