# frozen_string_literal: true

# == Schema Information
#
# Table name: chatbots
#
#  id           :uuid             not null, primary key
#  name         :string
#  description  :string
#  user_id      :uuid             not null
#  category     :integer          default("assistant"), not null
#  meta         :jsonb
#  source       :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  is_public    :boolean          default(FALSE), not null
#  expired_at   :datetime
#  access_count :integer          default(0)
#  object_type  :string
#  object_id    :uuid
#
class Chatbot < ApplicationRecord
  enum category: %i[assistant]

  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'
  belongs_to :object, polymorphic: true, optional: true, dependent: :destroy
  has_many :messages, -> { order(:created_at) }

  def increment_access_count!
    increment(:access_count).save
  end

  def has_expired?
    expired_at.present? && Time.current > expired_at
  end

  def add_message(role, object_type, content, meta)
    messages << Message.new(chatbot_id: id, role:, object_type:, content:, meta:)
  end

  def get_chatbot_messages
    messages.where("meta->>'belongs_user_id' = ?", current_user.id).order(created_at: :desc)
  end
end
