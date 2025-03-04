# frozen_string_literal: true

# == Schema Information
#
# Table name: conceptmaps
#
#  id           :bigint(8)        not null, primary key
#  name         :string
#  root_node    :uuid
#  status       :integer
#  introduction :string
#  meta         :jsonb            not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_conceptmaps_on_root_node  (root_node)
#
require 'test_helper'

class ConceptmapTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
