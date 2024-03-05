# frozen_string_literal: true

# == Schema Information
#
# Table name: public.user_marketplace_items
#
#  id                  :uuid             not null, primary key
#  user_type           :string           not null
#  user_id             :uuid             not null
#  marketplace_item_id :uuid             not null
#  custom_name         :string
#  custom_description  :text
#  purchase_id         :uuid             not null
#  meta                :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_user_marketplace_items_on_marketplace_item_id  (marketplace_item_id)
#  index_user_marketplace_items_on_purchase_id          (purchase_id)
#  index_user_marketplace_items_on_user                 (user_type,user_id)
#
# Foreign Keys
#
#  fk_rails_...  (marketplace_item_id => marketplace_items.id)
#  fk_rails_...  (purchase_id => purchases.id)
#
require 'test_helper'

class UserMarketplaceItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
