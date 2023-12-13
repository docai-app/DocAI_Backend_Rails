# frozen_string_literal: true

class AddObjectTypeAndObjectIdToTheStoryboardItem < ActiveRecord::Migration[7.0]
  def change
    remove_column :storyboard_items, :item_type
    remove_column :storyboard_items, :status
    add_column :storyboard_items, :status, :integer, default: 0, null: false, index: true
    add_column :storyboard_items, :object_type, :string, null: false, index: true
    add_column :storyboard_items, :object_id, :uuid, null: false, index: true
  end
end
