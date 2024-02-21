# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
#
#  id          :uuid             not null, primary key
#  chatbot_id  :uuid             not null
#  content     :text             not null
#  role        :string           default("user"), not null
#  user_id     :uuid
#  object_type :string           not null
#  is_read     :boolean          default(FALSE), not null
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_messages_on_chatbot_id   (chatbot_id)
#  index_messages_on_object_type  (object_type)
#  index_messages_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (chatbot_id => chatbots.id)
#  fk_rails_...  (user_id => users.id)
#
require 'test_helper'

class MessageTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
