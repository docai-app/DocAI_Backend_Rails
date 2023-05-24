# frozen_string_literal: true

class CreateFolderHierarchies < ActiveRecord::Migration[7.0]
  def change
    create_table :folder_hierarchies, id: false do |t|
      t.uuid :ancestor_id, null: false
      t.uuid :descendant_id, null: false
      t.integer :generations, null: false
    end

    add_index :folder_hierarchies, %i[ancestor_id descendant_id generations],
              unique: true,
              name: 'folder_anc_desc_idx'

    add_index :folder_hierarchies, [:descendant_id],
              name: 'folder_desc_idx'
  end
end
