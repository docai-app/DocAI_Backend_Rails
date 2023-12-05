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
class Message < ApplicationRecord
  store_accessor :meta, :belongs_user_id
  belongs_to :chatbot, class_name: 'Chatbot', foreign_key: 'chatbot_id', optional: true, dependent: :destroy

  has_paper_trail
end
