# frozen_string_literal: true

class CreateAssignmentReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_reminders, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :reminder_sender, foreign_key: { to_table: :general_users }, type: :uuid
      
      # 提醒類型（僅支持 email）
      t.integer :reminder_type, default: 0 # email
      
      # 提醒狀態
      t.integer :status, default: 0 # pending, sent, failed
      
      # 發送時間
      t.datetime :sent_at, null: true
      
      # 元數據
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    # 自定義索引名稱，避免自動生成的索引名過長
    add_index :assignment_reminders, [:essay_assignment_id, :general_user_id],
              name: 'idx_assignment_reminder_user'
    add_index :assignment_reminders, :status
    add_index :assignment_reminders, :reminder_type
  end
end
