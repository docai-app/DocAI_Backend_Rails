class CreateAgentTools < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_tools do |t|
      t.string :name
      t.string :invoke_name
      t.string :description
      t.string :invoke_description
      t.string :category
      t.jsonb :meta, default: {}, null: false

      t.timestamps
    end
    add_index :agent_tools, :category
  end
end
