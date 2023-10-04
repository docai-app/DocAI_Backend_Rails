# frozen_string_literal: true

class ChangeAssigneeIdToUuidOnProjectWorkflowStep < ActiveRecord::Migration[7.0]
  def change
    rename_column :project_workflow_steps, :assignee_id, :assignee_id_old
    add_column :project_workflow_steps, :assignee_id, :uuid, null: true, references: :users, index: true
    remove_column :project_workflow_steps, :assignee_id_old
  end
end
