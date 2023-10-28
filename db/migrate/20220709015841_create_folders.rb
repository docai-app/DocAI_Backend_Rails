# frozen_string_literal: true

class CreateFolders < ActiveRecord::Migration[7.0]
  def change
    create_table :folders, id: :uuid do |t|
      t.string :name
      t.uuid :parent_id
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :folders, :parent_id
  end
end
