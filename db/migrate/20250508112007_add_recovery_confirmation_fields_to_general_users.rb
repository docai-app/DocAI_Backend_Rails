class AddRecoveryConfirmationFieldsToGeneralUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :recovery_confirmation_token, :string
    add_column :general_users, :recovery_confirmation_sent_at, :datetime
  end
end
