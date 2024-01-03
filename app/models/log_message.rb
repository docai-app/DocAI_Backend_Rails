# frozen_string_literal: true

class LogMessage < ApplicationRecord
  belongs_to :chatbot, class_name: 'Chatbot', foreign_key: 'chatbot_id', optional: true, dependent: :destroy

  validates :content, presence: true
  validates :role, inclusion: { in: %w[user system] }
end
