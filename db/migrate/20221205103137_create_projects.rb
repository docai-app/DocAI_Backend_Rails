class CreateProjects < ActiveRecord::Migration[7.0]
  def change
    create_table :projects, id: :uuid do |t|
      t.string :name, null: false
      t.string :description, null: true, default: nil
      t.uuid :user_id, null: false
      t.uuid :folder_id, null: false
      t.boolean :is_public, default: false
      t.boolean :is_finished, default: false
      t.timestamps
      t.foreign_key :users, column: :user_id, primary_key: :id
      t.foreign_key :folders, column: :folder_id, primary_key: :id
    end
  end
end
