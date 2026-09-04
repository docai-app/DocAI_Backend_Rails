# frozen_string_literal: true

class CreateAssignmentPackages < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_packages, id: :uuid do |t|
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.uuid :learner_profile_id
      t.references :learning_path_template, null: true, foreign_key: true, type: :uuid
      t.string :title, null: false, default: 'Learning Package'
      t.text :description
      t.integer :status, null: false, default: 0
      t.jsonb :summary, null: false, default: {}
      t.jsonb :progress, null: false, default: {}
      t.jsonb :source_conversation, null: false, default: {}
      t.jsonb :dify_request, null: false, default: {}
      t.jsonb :dify_response, null: false, default: {}
      t.jsonb :error, null: false, default: {}
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :assignment_packages, :learner_profile_id
    add_index :assignment_packages, :status
    add_index :assignment_packages, %i[general_user_id status created_at], name: 'idx_assignment_packages_user_status_created'
    add_index :assignment_packages, %i[learning_path_template_id created_at], name: 'idx_assignment_packages_template_created'
  end
end
