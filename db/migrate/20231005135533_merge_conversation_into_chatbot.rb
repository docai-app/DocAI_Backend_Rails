# frozen_string_literal: true

class MergeConversationIntoChatbot < ActiveRecord::Migration[7.0]
  def change
    add_column :chatbots, :object_type, :string, null: true, index: true
    add_column :chatbots, :object_id, :uuid, null: true
  end

  def down
    remove_column :chatbots, :object_type
    remove_column :chatbots, :object_id
  end
end
