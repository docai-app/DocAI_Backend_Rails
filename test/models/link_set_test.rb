# frozen_string_literal: true

# == Schema Information
#
# Table name: link_sets
#
#  id             :bigint(8)        not null, primary key
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  description    :string
#  user_id        :uuid
#  slug           :string
#  request_origin :string
#  workspace      :string
#
# Indexes
#
#  index_link_sets_on_slug       (slug) UNIQUE
#  index_link_sets_on_user_id    (user_id)
#  index_link_sets_on_workspace  (workspace)
#
require 'test_helper'

class LinkSetTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
