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
#
class Chatbot < ApplicationRecord
  resourcify
  has_paper_trail

  enum category: %i[qa chart_generation statistical_generation]

  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'
  belongs_to :object, polymorphic: true, optional: true, dependent: :destroy
  has_many :messages, -> { order('messages.created_at') }, dependent: :destroy
  has_many :log_messages, -> { order('log_messages.created_at') }, dependent: :destroy

  after_create :set_permissions_to_owner

  def set_permissions_to_owner
    return if self['user_id'].nil?

    user.add_role :r, self
    user.add_role :w, self
  end

  def has_rights_to_read?(user)
    return true if user_id.nil?

    user.has_role? :r, self
  end

  def has_rights_to_write?(user)
    return true if user_id.nil?

    user.has_role? :w, self
  end

  def has_rights_to_read_and_write?(user)
    return true if user_id.nil?

    user.has_role? :r, self
    user.has_role? :w, self
  end

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

  def update_assistive_questions(getSubdomain, metadata)
    res = AiService.assistantQASuggestion(getSubdomain, metadata)
    puts "Res: #{res}"
    if res['assistant_questions'].present?
      puts "Res assistive_questions: #{res['assistant_questions']}"
      self.assistive_questions = res['assistant_questions']
    else
      self.assistive_questions = []
    end
    save
  end

  def assistant
    return if meta['assistant'].nil?

    AssistantAgent.find(meta['assistant'])
  end

  def experts
    return [] if meta['experts'].nil?

    AssistantAgent.includes(:agent_tools).where(id: meta['experts'])
  end
end
