class AddDifyConversationIdToMessage < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :dify_conversation_id, :string
    add_index :messages, :dify_conversation_id
  end
end
