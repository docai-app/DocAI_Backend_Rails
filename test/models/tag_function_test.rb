# frozen_string_literal: true

# == Schema Information
#
# Table name: tag_functions
#
#  id          :uuid             not null, primary key
#  tag_id      :uuid             not null
#  function_id :uuid             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tag_functions_on_function_id  (function_id)
#  index_tag_functions_on_function_id  (function_id)
#  index_tag_functions_on_tag_id       (tag_id)
#  index_tag_functions_on_tag_id       (tag_id)
#
require 'test_helper'

class TagFunctionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
