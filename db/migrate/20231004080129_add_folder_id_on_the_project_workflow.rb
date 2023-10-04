# frozen_string_literal: true

class AddFolderIdOnTheProjectWorkflow < ActiveRecord::Migration[7.0]
  def change
    add_reference :project_workflows, :folder, foreign_key: true, type: :uuid
    rename_column :project_workflows, :used_id, :user_id
  end
end
