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
require 'test_helper'

class LogMessageTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
