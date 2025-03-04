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
# Indexes
#
#  index_storyboard_item_associations_on_storyboard_id       (storyboard_id)
#  index_storyboard_item_associations_on_storyboard_item_id  (storyboard_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (storyboard_id => storyboards.id)
#  fk_rails_...  (storyboard_item_id => storyboard_items.id)
#
class StoryboardItemAssociation < ApplicationRecord
  belongs_to :storyboard
  belongs_to :storyboard_item
end
