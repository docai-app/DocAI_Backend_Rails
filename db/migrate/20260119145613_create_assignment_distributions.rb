# frozen_string_literal: true

class CreateAssignmentDistributions < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_distributions, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: false, foreign_key: true, type: :uuid
      t.references :school, null: false, foreign_key: true, type: :uuid
      
      # 分配類型：class_name（班級）、individual（個別學生）
      t.string :distribution_type, null: false
      
      # 分配目標：班級名稱或學生ID
      t.string :target_class_name
      t.references :target_student, foreign_key: { to_table: :general_users }, type: :uuid
      
      # 截止日期
      t.datetime :deadline, null: true
      
      # 狀態
      t.integer :status, default: 0 # active, cancelled
      
      # 元數據（可擴展）
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    add_index :assignment_distributions, [:essay_assignment_id, :school_academic_year_id], 
              name: 'index_assignment_distributions_on_assignment_and_year'
    add_index :assignment_distributions, [:distribution_type, :target_class_name], 
              name: 'index_assignment_distributions_on_type_and_class'
    # target_student_id 索引已由 t.references 自动创建，无需重复添加
    # add_index :assignment_distributions, :target_student_id
    add_index :assignment_distributions, :deadline
    add_index :assignment_distributions, :status
  end
end
