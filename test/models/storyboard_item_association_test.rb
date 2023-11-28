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
require 'test_helper'

class StoryboardItemAssociationTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
