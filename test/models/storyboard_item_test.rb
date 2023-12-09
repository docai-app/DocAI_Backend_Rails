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
#  data        :text             default("")
#  sql         :text             default("")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  is_ready    :boolean          default(FALSE), not null
#  status      :integer          default("cached"), not null
#  object_type :string           not null
#  object_id   :uuid             not null
#  item_type   :string
#
require 'test_helper'

class StoryboardItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
