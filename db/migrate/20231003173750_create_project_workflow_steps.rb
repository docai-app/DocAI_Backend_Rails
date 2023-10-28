# frozen_string_literal: true

class CreateProjectWorkflowSteps < ActiveRecord::Migration[7.0]
  def change
    create_table :project_workflow_steps, id: :uuid do |t|
      t.integer :position
      t.string :name, null: false
      t.string :description, null: true
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.integer :assignee_id, null: true
      t.references :project_workflow, null: false, foreign_key: true, type: :uuid
      t.integer :status, default: 0
      t.boolean :is_human, default: true
      t.jsonb :meta, default: {}
      t.jsonb :dag_meta, default: {}
      t.datetime :deadline
      t.timestamps
    end
    add_index :project_workflow_steps, :assignee_id
    add_index :project_workflow_steps, :status
  end
end
