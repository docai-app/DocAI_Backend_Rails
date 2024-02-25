# frozen_string_literal: true

# == Schema Information
#
# Table name: public.marketplace_items
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
# Indexes
#
#  index_marketplace_items_on_entity_name  (entity_name)
#
require 'test_helper'

class MarketplaceItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
