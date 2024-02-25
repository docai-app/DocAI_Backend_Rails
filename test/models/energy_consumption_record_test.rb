# frozen_string_literal: true

# == Schema Information
#
# Table name: public.energy_consumption_records
#
#  id                  :uuid             not null, primary key
#  marketplace_item_id :uuid             not null
#  energy_consumed     :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  user_type           :string           not null
#  user_id             :uuid             not null
#
# Indexes
#
#  index_energy_consumption_records_on_marketplace_item_id  (marketplace_item_id)
#  index_energy_consumption_records_on_user                 (user_type,user_id)
#
require 'test_helper'

class EnergyConsumptionRecordTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
