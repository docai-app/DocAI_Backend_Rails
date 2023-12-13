# frozen_string_literal: true

class CreateStoryboardItemAssociations < ActiveRecord::Migration[7.0]
  def change
    create_table :storyboard_item_associations, id: :uuid do |t|
      t.references :storyboard, null: false, foreign_key: true, type: :uuid, index: true
      t.references :storyboard_item, null: false, foreign_key: true, type: :uuid, index: true

      t.timestamps
    end
  end
end
