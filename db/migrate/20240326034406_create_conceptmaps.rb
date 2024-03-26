class CreateConceptmaps < ActiveRecord::Migration[7.0]
  def change
    create_table :conceptmaps do |t|
      t.string :name
      t.uuid :root_node
      t.integer :status
      t.string :introduction
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
    add_index :conceptmaps, :root_node
  end
end
