class AddPromptHeaderToAssistantAgent < ActiveRecord::Migration[7.0]
  def change
    add_column :assistant_agents, :prompt_header, :string
  end
end
