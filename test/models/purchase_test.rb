# frozen_string_literal: true

# == Schema Information
#
# Table name: public.purchases
#
#  id                  :uuid             not null, primary key
#  user_type           :string           not null
#  user_id             :uuid             not null
#  marketplace_item_id :uuid             not null
#  purchased_at        :datetime
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_purchases_on_marketplace_item_id  (marketplace_item_id)
#  index_purchases_on_user                 (user_type,user_id)
#
# Foreign Keys
#
#  fk_rails_...  (marketplace_item_id => public.marketplace_items.id)
#
require 'test_helper'

class PurchaseTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
