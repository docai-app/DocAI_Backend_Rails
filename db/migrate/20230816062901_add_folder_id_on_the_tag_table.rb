class AddFolderIdOnTheTagTable < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :folder_id, :uuid, default: nil, null: true, index: true
    add_column :tags, :user_id, :uuid, default: nil, null: true, index: true
  end
end
