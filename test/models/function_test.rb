# frozen_string_literal: true

# == Schema Information
#
# Table name: functions
#
#  id          :uuid             not null, primary key
#  name        :string
#  description :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  title       :string           default(""), not null
#
require 'test_helper'

class FunctionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
