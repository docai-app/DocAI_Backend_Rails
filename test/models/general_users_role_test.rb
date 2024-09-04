# frozen_string_literal: true

# == Schema Information
#
# Table name: public.general_users_roles
#
#  general_user_id :uuid             not null
#  role_id         :uuid             not null
#
# Indexes
#
#  index_general_users_roles_on_general_user_id  (general_user_id)
#  index_general_users_roles_on_role_id          (role_id)
#
require 'test_helper'

class GeneralUsersRoleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end