# frozen_string_literal: true

class CreateAssignmentPackageItems < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_package_items, id: :uuid do |t|
      t.references :assignment_package, null: false, foreign_key: true, type: :uuid
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.integer :position, null: false
      t.integer :status, null: false, default: 0
      t.uuid :essay_grading_id
      t.string :title
      t.string :category
      t.jsonb :meta, null: false, default: {}
      t.datetime :unlocked_at
      t.datetime :completed_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :assignment_package_items, %i[assignment_package_id position], unique: true, name: 'idx_package_items_package_position'
    add_index :assignment_package_items, %i[assignment_package_id essay_assignment_id], unique: true, name: 'idx_package_items_package_assignment'
    add_index :assignment_package_items, %i[assignment_package_id status], name: 'idx_package_items_package_status'
    add_index :assignment_package_items, :essay_grading_id
  end
end
