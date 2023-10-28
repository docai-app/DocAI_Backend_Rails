# frozen_string_literal: true

class ChangeProjectWorkflowIdNullableOnTheProjectWorkflowStep < ActiveRecord::Migration[7.0]
  def change
    change_column :project_workflow_steps, :project_workflow_id, :uuid, null: true, default: nil, index: true,
                                                                        foreign_key: true
  end
end
