# frozen_string_literal: true

class AddUserTypeToMessage < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :user_type, :string
    add_index :messages, %i[user_id user_type]
  end
end
