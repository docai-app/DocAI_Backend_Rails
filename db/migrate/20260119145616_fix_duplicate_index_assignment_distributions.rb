# frozen_string_literal: true

class FixDuplicateIndexAssignmentDistributions < ActiveRecord::Migration[7.0]
  def up
    # 如果索引已存在，先删除它（因为 t.references 已经自动创建了）
    if index_exists?(:assignment_distributions, :target_student_id, name: 'index_assignment_distributions_on_target_student_id')
      remove_index :assignment_distributions, name: 'index_assignment_distributions_on_target_student_id'
    end
  end

  def down
    # 回滚时不需要做什么，因为索引应该由 t.references 自动创建
  end
end
