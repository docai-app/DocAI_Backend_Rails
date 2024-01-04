# frozen_string_literal: true

class CreateAssistantAgents < ActiveRecord::Migration[7.0]
  def change
    create_table :assistant_agents do |t|
      t.string :name
      t.string :description
      t.string :system_message
      t.string :subdomain
      t.jsonb :llm_config
      t.jsonb :meta

      t.timestamps
    end
  end
end
