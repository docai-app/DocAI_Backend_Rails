# frozen_string_literal: true

# == Schema Information
#
# Table name: marketplace_items
#
#  id                  :uuid             not null, primary key
#  chatbot_id          :uuid
#  user_id             :uuid
#  entity_name         :string           not null
#  chatbot_name        :string           not null
#  chatbot_description :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
require 'test_helper'

class MarketplaceItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
