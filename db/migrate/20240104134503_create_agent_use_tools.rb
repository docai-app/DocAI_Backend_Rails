class CreateAgentUseTools < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_use_tools do |t|
      t.references :assistant_agent, null: false, foreign_key: true
      t.references :agent_tool, null: false, foreign_key: true

      t.timestamps
    end
  end
end
