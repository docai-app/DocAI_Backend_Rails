# frozen_string_literal: true

class StoryboardItem < ApplicationRecord
  has_many :storyboard_item_associations
  has_many :storyboards, through: :storyboard_item_associations
end
