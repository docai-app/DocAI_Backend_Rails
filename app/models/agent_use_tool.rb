# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_use_tools
#
#  id                 :bigint           not null, primary key
#  assistant_agent_id :bigint           not null
#  agent_tool_id      :bigint           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class AgentUseTool < ApplicationRecord
  belongs_to :assistant_agent
  belongs_to :agent_tool
end
