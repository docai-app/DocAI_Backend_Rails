# frozen_string_literal: true

class AddSomeDefaultName < ActiveRecord::Migration[7.0]
  def change
    change_column :projects, :name, :string, null: false, default: 'New Project'
    change_column :project_tasks, :title, :string, null: false, default: 'New Project Task'
    change_column :folders, :name, :string, null: false, default: 'New Folder'

    add_column :project_tasks, :deadline_at, :timestamp, null: true, default: nil
  end
end
