class CreateMemberships < ActiveRecord::Migration[7.0]
  def change
    create_table :memberships, id: :uuid do |t|
      t.uuid :general_user_id, null: false
      t.uuid :group_id, null: false

      t.timestamps
    end

    add_foreign_key :memberships, :general_users, column: :general_user_id
    add_foreign_key :memberships, :groups, column: :group_id
  end
end
