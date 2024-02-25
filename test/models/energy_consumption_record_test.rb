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
require 'test_helper'

class EnergyConsumptionRecordTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
