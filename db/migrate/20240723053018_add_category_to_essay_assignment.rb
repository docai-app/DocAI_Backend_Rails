class AddCategoryToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :category, :integer, null: false, default: 0
    add_index :essay_assignments, :category
    add_column :essay_assignments, :title, :string
    add_column :essay_assignments, :hints, :string
  end
end
