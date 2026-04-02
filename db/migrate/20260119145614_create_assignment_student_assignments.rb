# frozen_string_literal: true

class CreateAssignmentStudentAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_student_assignments, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      # 自定義索引名稱，避免自動生成的索引名過長（PostgreSQL 限制 63 字符）
      t.references :assignment_distribution,
                   null: false,
                   foreign_key: true,
                   type: :uuid,
                   index: { name: 'idx_assignment_distribution_id' }
      
      # 分配狀態
      t.integer :status, default: 0 # assigned, completed, overdue
      
      # 截止日期（從 distribution 複製，但可個別調整）
      t.datetime :deadline, null: true
      
      # 完成時間
      t.datetime :completed_at, null: true
      
      # 元數據
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    add_index :assignment_student_assignments, [:essay_assignment_id, :general_user_id], 
              unique: true, name: 'index_assignment_student_assignments_unique'
    # 自定義索引名稱，避免自動生成的索引名過長
    add_index :assignment_student_assignments, [:general_user_id, :status],
              name: 'idx_assignment_user_status'
    add_index :assignment_student_assignments, :deadline
    add_index :assignment_student_assignments, :status
  end
end
