class AddIsCheckOnTagsTable < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :is_checked, :boolean, default: false
  end
end
