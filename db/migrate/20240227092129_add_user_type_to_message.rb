class AddUserTypeToMessage < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :user_type, :string
    add_index :messages, [:user_id, :user_type]
  end
end
