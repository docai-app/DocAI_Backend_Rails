# frozen_string_literal: true

class AddDifyConversationIdToLogMessage < ActiveRecord::Migration[7.0]
  def change
    add_column :log_messages, :dify_conversation_id, :string
    add_index :log_messages, :dify_conversation_id
  end
end
