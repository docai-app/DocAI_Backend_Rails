# frozen_string_literal: true

# == Schema Information
#
# Table name: log_messages
#
#  id                  :uuid             not null, primary key
#  chatbot_id          :uuid             not null
#  session_id          :uuid             not null
#  content             :text             default(""), not null
#  role                :string
#  previous_message_id :uuid
#  has_chat_history    :boolean          default(FALSE)
#  meta                :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class LogMessage < ApplicationRecord
  belongs_to :chatbot, class_name: 'Chatbot', foreign_key: 'chatbot_id', optional: true, dependent: :destroy

  validates :content, presence: true
  validates :role, inclusion: { in: %w[user system] }
end
