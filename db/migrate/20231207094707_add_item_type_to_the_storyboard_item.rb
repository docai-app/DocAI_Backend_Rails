# frozen_string_literal: true

class AddItemTypeToTheStoryboardItem < ActiveRecord::Migration[7.0]
  def change
    add_column :storyboard_items, :item_type, :string, null: true, default: nil, index: true

    StoryboardItem.all.each do |item|
      if item.object_type == 'SmartExtractionSchema_Chart'
        item.update!(item_type: 'chart', object_type: 'SmartExtractionSchema')
      elsif item.object_type == 'SmartExtractionSchema_Statistics'
        item.update!(item_type: 'statistics', object_type: 'SmartExtractionSchema')
      end
    end
  end
end
