# frozen_string_literal: true

class ChangeKgLinkerUuid < ActiveRecord::Migration[7.0]
  def up
    # 为map_from_id和map_to_id添加新的UUID列
    add_column :kg_linkers, :new_map_from_id, :uuid
    add_column :kg_linkers, :new_map_to_id, :uuid

    # 这里添加数据迁移逻辑，更新new_map_from_id和new_map_to_id

    # 删除原始的bigint列
    remove_column :kg_linkers, :map_from_id
    remove_column :kg_linkers, :map_to_id

    # 重命名新列为原始列名
    rename_column :kg_linkers, :new_map_from_id, :map_from_id
    rename_column :kg_linkers, :new_map_to_id, :map_to_id

    # 为新的UUID列添加索引
    add_index :kg_linkers, :map_from_id
    add_index :kg_linkers, :map_to_id
  end

  def down
    # 逆向迁移逻辑，从uuid转回bigint
    # 请注意，这通常不是直接可能的，因为原始的bigint值已经不可恢复
    # 如果你需要能够回滚到bigint，你需要在up迁移中妥善处理数据迁移逻辑
  end
end
