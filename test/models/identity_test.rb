# frozen_string_literal: true

# == Schema Information
#
# Table name: identities
#
#  id         :uuid             not null, primary key
#  user_id    :uuid             not null
#  provider   :string
#  uid        :string
#  metadata   :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'test_helper'

class IdentityTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
