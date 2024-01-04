# frozen_string_literal: true

class CreateLogMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :log_messages, id: :uuid do |t|
      t.uuid :chatbot_id, null: false, index: true
      t.uuid :session_id, null: false, index: true
      t.text :content, null: false, default: ''
      t.string :role # 'user' or 'system'
      t.uuid :previous_message_id, null: true
      t.boolean :has_chat_history, default: false
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
  end
end
