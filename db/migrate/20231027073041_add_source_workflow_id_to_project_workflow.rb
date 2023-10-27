class AddSourceWorkflowIdToProjectWorkflow < ActiveRecord::Migration[7.0]
  def change
    add_column :project_workflows, :source_workflow_id, :integer
    add_index :project_workflows, :source_workflow_id
  end
end
