# frozen_string_literal: true

# == Schema Information
#
# Table name: storyboard_items
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :text
#  user_id     :uuid             not null
#  query       :string           not null
#  item_type   :string           not null
#  data        :text             default("")
#  sql         :text             default("")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require 'test_helper'

class StoryboardItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
