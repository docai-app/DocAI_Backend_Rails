# frozen_string_literal: true

class ChangeFolderUserIdNullable < ActiveRecord::Migration[7.0]
  def change
    change_column :folders, :user_id, :uuid, null: true, default: nil, index: true
  end
end
