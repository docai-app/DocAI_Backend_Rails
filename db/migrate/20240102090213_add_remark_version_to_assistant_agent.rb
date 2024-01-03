# frozen_string_literal: true

class AddRemarkVersionToAssistantAgent < ActiveRecord::Migration[7.0]
  def change
    add_column :assistant_agents, :remark, :string
    add_column :assistant_agents, :version, :string
    add_column :assistant_agents, :name_en, :string
    add_index :assistant_agents, :version
    add_index :assistant_agents, :name_en
    add_index :assistant_agents, :name
  end
end
