# frozen_string_literal: true

class AddAssistiveQuestionsToChatbots < ActiveRecord::Migration[7.0]
  def change
    add_column :chatbots, :assistive_questions, :jsonb, null: false, default: []
    add_column :chatbots, :has_chatbot_updated, :boolean, null: false, default: false
  end
end
