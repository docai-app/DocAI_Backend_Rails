class AgentUseTool < ApplicationRecord
  belongs_to :assistant_agent
  belongs_to :agent_tool
end
