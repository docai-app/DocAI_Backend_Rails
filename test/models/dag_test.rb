# frozen_string_literal: true

# == Schema Information
#
# Table name: dags
#
#  id         :uuid             not null, primary key
#  user_id    :uuid
#  name       :string
#  meta       :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'test_helper'

class DagTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
