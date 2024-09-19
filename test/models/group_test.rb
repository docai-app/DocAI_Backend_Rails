# frozen_string_literal: true

# == Schema Information
#
# Table name: public.groups
#
#  name       :string           not null
#  owner_id   :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  id         :uuid             not null, primary key
#
# Foreign Keys
#
#  groups_owner_id_fkey  (owner_id => public.general_users.id)
#
require 'test_helper'

class GroupTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
