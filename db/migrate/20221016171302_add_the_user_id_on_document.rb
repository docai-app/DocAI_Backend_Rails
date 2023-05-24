# frozen_string_literal: true

class AddTheUserIdOnDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :user_id, :uuid, null: true, default: nil
    add_index :documents, :user_id
  end
end
