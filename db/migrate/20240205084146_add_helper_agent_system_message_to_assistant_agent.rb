class AddHelperAgentSystemMessageToAssistantAgent < ActiveRecord::Migration[7.0]
  def change
    add_column :assistant_agents, :helper_agent_system_message, :string
  end
end
