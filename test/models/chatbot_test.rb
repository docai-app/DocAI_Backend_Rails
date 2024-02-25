# frozen_string_literal: true

# == Schema Information
#
# Table name: chatbots
#
#  id                  :uuid             not null, primary key
#  name                :string
#  description         :string
#  user_id             :uuid             not null
#  category            :integer          default("qa"), not null
#  meta                :jsonb
#  source              :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  is_public           :boolean          default(FALSE), not null
#  expired_at          :datetime
#  access_count        :integer          default(0)
#  object_type         :string
#  object_id           :uuid
#  assistive_questions :jsonb            not null
#  has_chatbot_updated :boolean          default(FALSE), not null
#  energy_cost         :integer          default(0)
#
require 'test_helper'

class ChatbotTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
