class CreateGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :groups, id: :uuid do |t|
      t.string :name, null: false
      t.uuid :owner_id, null: false
      t.foreign_key :general_users, column: :owner_id, primary_key: :id
      t.timestamps
    end
  end
end