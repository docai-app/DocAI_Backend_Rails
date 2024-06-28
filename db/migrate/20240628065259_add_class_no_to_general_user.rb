class AddClassNoToGeneralUser < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :class, :string
    add_column :general_users, :no, :string
  end
end
