# frozen_string_literal: true

class AddLockableToGeneralUser < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :failed_attempts, :integer, default: 0
    add_column :general_users, :unlock_token, :string
    add_column :general_users, :locked_at, :datetime
  end
end
