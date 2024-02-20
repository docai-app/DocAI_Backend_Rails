class AddConcludeConversationMessage < ActiveRecord::Migration[7.0]
  def change
    add_column :assistant_agents, :conclude_conversation_message, :string
  end
end
