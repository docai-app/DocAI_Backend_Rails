# frozen_string_literal: true

class AddIsTemplateToTheProjectWorkflow < ActiveRecord::Migration[7.0]
  def change
    add_column :project_workflows, :is_template, :boolean, default: false, null: false, index: true
  end
end
