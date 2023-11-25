# frozen_string_literal: true

class RemoveForeignKeyFromApiKeys < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :api_keys, :users if foreign_key_exists?(:api_keys, :users)

    change_column :api_keys, :user_id, :uuid, null: false, index: true
  end
end
