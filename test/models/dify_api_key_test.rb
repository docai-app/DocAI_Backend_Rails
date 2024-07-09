# frozen_string_literal: true

# == Schema Information
#
# Table name: public.dify_api_keys
#
#  id         :uuid             not null, primary key
#  domain     :string           not null
#  workspace  :string           not null
#  api_key    :string           not null
#  actived_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_dify_api_keys_on_domain_and_workspace  (domain,workspace) UNIQUE
#
require 'test_helper'

class DifyApiKeyTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
