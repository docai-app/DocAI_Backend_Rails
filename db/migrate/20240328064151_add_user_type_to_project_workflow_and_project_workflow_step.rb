# frozen_string_literal: true

class AddUserTypeToProjectWorkflowAndProjectWorkflowStep < ActiveRecord::Migration[7.0]
  def change
    add_column :project_workflows, :user_type, :string, null: false, default: 'User'
    add_column :project_workflow_steps, :user_type, :string, null: false, default: 'User'
  end
end
