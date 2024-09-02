# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_use_tools
#
#  id                 :bigint(8)        not null, primary key
#  assistant_agent_id :bigint(8)        not null
#  agent_tool_id      :bigint(8)        not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_agent_use_tools_on_agent_tool_id       (agent_tool_id)
#  index_agent_use_tools_on_assistant_agent_id  (assistant_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (agent_tool_id => public.agent_tools.id)
#  fk_rails_...  (assistant_agent_id => public.assistant_agents.id)
#
require 'test_helper'

class AgentUseToolTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
