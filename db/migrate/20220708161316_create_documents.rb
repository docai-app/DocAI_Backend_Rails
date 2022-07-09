class CreateDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :documents, id: :uuid do |t|
      t.string :name
      t.string :storage_url
      t.text :content
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :documents, :status
    add_index :documents, :name
  end
end
