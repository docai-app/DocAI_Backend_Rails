# frozen_string_literal: true

# == Schema Information
#
# Table name: public.roles
#
#  id            :uuid             not null, primary key
#  name          :string
#  resource_type :string
#  resource_id   :uuid
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_roles_on_name_and_resource_type_and_resource_id  (name,resource_type,resource_id)
#  index_roles_on_resource                                (resource_type,resource_id)
#
require 'test_helper'

class RoleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
