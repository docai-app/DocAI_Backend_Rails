# frozen_string_literal: true

class CreateSupplementPracticeRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :supplement_practice_records, id: :uuid do |t|
      # 关联字段
      t.references :essay_grading, null: false, foreign_key: true, type: :uuid, index: true
      t.references :general_user, null: false, foreign_key: true, type: :uuid, index: true
      
      # 状态：draft（草稿）、submitted（已提交）
      t.integer :status, default: 0, null: false
      
      # 分数信息
      t.decimal :score, precision: 10, scale: 2, default: 0.0
      t.decimal :full_score, precision: 10, scale: 2, default: 0.0
      t.integer :questions_count, default: 0
      
      # 时间记录
      t.integer :using_time, default: 0, comment: '完成用时（秒）'
      t.datetime :started_at, comment: '开始时间'
      t.datetime :submitted_at, comment: '提交时间'
      
      # 答案数据（JSONB）
      t.jsonb :answers, default: {}, null: false
      
      # 原始题目数据（JSONB，从 supplement_practice 解析后存储）
      t.jsonb :questions_data, default: {}, null: false
      
      # 元数据
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end
    
    # 索引
    add_index :supplement_practice_records, [:essay_grading_id, :general_user_id], 
              name: 'index_supplement_practice_on_grading_and_user'
    add_index :supplement_practice_records, :status
    add_index :supplement_practice_records, :submitted_at
    add_index :supplement_practice_records, [:general_user_id, :status]
    
    # 唯一约束：每个 essay_grading 和 general_user 组合只能有一条 submitted 记录
    # 但可以有多个 draft 记录（允许多次保存草稿）
    # 注意：PostgreSQL 的 partial unique index 语法
    add_index :supplement_practice_records, 
              [:essay_grading_id, :general_user_id], 
              unique: true, 
              where: "status = 1", # 只对 submitted 状态应用唯一约束
              name: 'index_supplement_practice_unique_submitted'
  end
end
