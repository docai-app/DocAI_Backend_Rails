# frozen_string_literal: true

# == Schema Information
#
# Table name: public.api_keys
#
#  id          :uuid             not null, primary key
#  user_id     :uuid             not null
#  key         :string           not null
#  expires_at  :datetime
#  active      :boolean          default(TRUE)
#  tenant      :string           not null
#  name        :string
#  description :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_api_keys_on_key      (key) UNIQUE
#  index_api_keys_on_tenant   (tenant)
#  index_api_keys_on_user_id  (user_id)
#
require 'test_helper'

class ApiKeyTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
