# frozen_string_literal: true

# == Schema Information
#
# Table name: groups
#
#  name       :string           not null
#  owner_id   :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  id         :uuid             not null, primary key
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => general_users.id)
#
require 'test_helper'

class GroupTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
