# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_tools
#
#  id                 :bigint(8)        not null, primary key
#  name               :string
#  invoke_name        :string
#  description        :string
#  invoke_description :string
#  category           :string
#  meta               :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_agent_tools_on_category  (category)
#
require 'test_helper'

class AgentToolTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
