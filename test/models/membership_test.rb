# frozen_string_literal: true

# == Schema Information
#
# Table name: public.memberships
#
#  id              :uuid             not null, primary key
#  general_user_id :uuid             not null
#  group_id        :uuid             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => public.general_users.id)
#  fk_rails_...  (group_id => public.groups.id)
#
require 'test_helper'

class MembershipTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
