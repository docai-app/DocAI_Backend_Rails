# frozen_string_literal: true

class AddStatusAndToTheStoryboardItem < ActiveRecord::Migration[7.0]
  def change
    add_column :storyboard_items, :status, :string, default: 'cached', null: false, index: true
    add_column :storyboard_items, :is_ready, :boolean, default: false, null: false, index: true
  end
end
