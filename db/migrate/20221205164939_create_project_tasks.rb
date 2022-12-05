class CreateProjectTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :project_tasks, id: :uuid do |t|
      t.string :title, null: false
      t.text :description, null: true, default: nil
      t.uuid :project_id, null: false, index: true, foreign_key: true
      t.uuid :user_id, null: false, index: true, foreign_key: true
      t.boolean :is_completed, null: false, default: false
      t.integer :order, null: false, default: 0
      t.timestamps
    end
  end
end
