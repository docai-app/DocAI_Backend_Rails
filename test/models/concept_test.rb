# frozen_string_literal: true

# == Schema Information
#
# Table name: concepts
#
#  id         :bigint(8)        not null, primary key
#  source     :string
#  name       :string
#  root_node  :uuid
#  meta       :jsonb            not null
#  sort       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_concepts_on_root_node  (root_node)
#
require 'test_helper'

class ConceptTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
