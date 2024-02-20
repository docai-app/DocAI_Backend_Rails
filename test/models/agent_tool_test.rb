# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_tools
#
#  id                 :bigint           not null, primary key
#  name               :string
#  invoke_name        :string
#  description        :string
#  invoke_description :string
#  category           :string
#  meta               :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
require 'test_helper'

class AgentToolTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
