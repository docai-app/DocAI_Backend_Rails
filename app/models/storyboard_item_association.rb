# frozen_string_literal: true

# == Schema Information
#
# Table name: storyboard_item_associations
#
#  id                 :uuid             not null, primary key
#  storyboard_id      :uuid             not null
#  storyboard_item_id :uuid             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class StoryboardItemAssociation < ApplicationRecord
  belongs_to :storyboard
  belongs_to :storyboard_item
end
