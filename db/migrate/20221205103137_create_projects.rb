class CreateProjects < ActiveRecord::Migration[7.0]
  def change
    create_table :projects, id: :uuid do |t|
      t.string :name
      t.string :description
      t.uuid :user_id
      t.string :folder_id
      t.boolean :is_public, default: false
      t.boolean :is_finished, default: false
      t.timestamps
    end
  end
end
