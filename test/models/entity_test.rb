# frozen_string_literal: true

# == Schema Information
#
# Table name: public.entities
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :string           default("")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require 'test_helper'

class EntityTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
