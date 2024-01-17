class AddCategoryToAssistantAgents < ActiveRecord::Migration[7.0]
  def change
    add_column :assistant_agents, :category, :string
    add_index :assistant_agents, :category
  end
end
