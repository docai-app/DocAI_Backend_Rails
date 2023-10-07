# frozen_string_literal: true

# == Schema Information
#
# Table name: dags
#
#  id         :uuid             not null, primary key
#  user_id    :uuid
#  dag_name   :string
#  dag_status :integer          default("pending")
#  meta       :jsonb
#  statistic  :jsonb
#  dag_meta   :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'test_helper'

class DagTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
