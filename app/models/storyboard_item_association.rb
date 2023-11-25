# frozen_string_literal: true

class StoryboardItemAssociation < ApplicationRecord
  belongs_to :storyboard
  belongs_to :storyboard_item
end
