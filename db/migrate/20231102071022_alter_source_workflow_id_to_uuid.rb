class AlterSourceWorkflowIdToUuid < ActiveRecord::Migration[7.0]
  def change
    remove_column :project_workflows, :source_workflow_id
    add_column :project_workflows, :source_workflow_id, :uuid
    add_index :project_workflows, :source_workflow_id
  end
end
