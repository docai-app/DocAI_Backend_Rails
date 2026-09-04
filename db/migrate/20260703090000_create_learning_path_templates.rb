# frozen_string_literal: true

class CreateLearningPathTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :learning_path_templates, id: :uuid do |t|
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.string :level
      t.string :locale
      t.string :category, null: false, default: 'talk_lab_package'
      t.jsonb :prompt_config, null: false, default: {}
      t.jsonb :dify_config, null: false, default: {}
      t.jsonb :usage_policy, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.uuid :created_by_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :learning_path_templates, :status
    add_index :learning_path_templates, :category
    add_index :learning_path_templates, :position
    add_index :learning_path_templates, :created_by_id
  end
end
