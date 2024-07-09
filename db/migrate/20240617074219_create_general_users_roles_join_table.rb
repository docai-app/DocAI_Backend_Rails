# frozen_string_literal: true

class CreateGeneralUsersRolesJoinTable < ActiveRecord::Migration[7.0]
  def change
    create_table :general_users_roles, id: false do |t|
      t.uuid :general_user_id, null: false
      t.uuid :role_id, null: false
    end

    add_index :general_users_roles, :general_user_id
    add_index :general_users_roles, :role_id
  end
end
