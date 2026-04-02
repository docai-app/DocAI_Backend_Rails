# frozen_string_literal: true

class AddEssayAssignmentIdToSupplementPracticeRecords < ActiveRecord::Migration[7.0]
  def change
    add_reference :supplement_practice_records, :essay_assignment, null: true, foreign_key: true, type: :uuid, index: true
    
    # 为已存在的记录填充 essay_assignment_id
    # 通过 essay_grading 关联获取
    execute <<-SQL
      UPDATE supplement_practice_records
      SET essay_assignment_id = essay_gradings.essay_assignment_id
      FROM essay_gradings
      WHERE supplement_practice_records.essay_grading_id = essay_gradings.id
        AND supplement_practice_records.essay_assignment_id IS NULL;
    SQL
    
    # 将字段设置为 NOT NULL（在填充数据后）
    change_column_null :supplement_practice_records, :essay_assignment_id, false
    
    # 添加索引以优化通过 essay_assignment_id 查询
    add_index :supplement_practice_records, [:essay_assignment_id, :status], 
              name: 'index_supplement_practice_on_assignment_and_status'
  end
end
