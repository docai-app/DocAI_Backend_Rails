# frozen_string_literal: true

class AddRecoveryEmailToGeneralUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :recovery_email, :string
    add_column :general_users, :recovery_email_confirmed_at, :datetime

    # 為 recovery_email 添加索引以優化查詢
    add_index :general_users, :recovery_email
  end
end
