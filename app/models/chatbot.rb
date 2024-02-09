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
#  energy_cost         :integer          default(1)
#
class Chatbot < ApplicationRecord
  resourcify
  has_paper_trail

  enum category: %i[qa chart_generation statistical_generation]

  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'
  belongs_to :object, polymorphic: true, optional: true, dependent: :destroy
  has_many :messages, -> { order('messages.created_at') }, dependent: :destroy
  has_many :log_messages, -> { order('log_messages.created_at') }, dependent: :destroy
  has_one :marketplace_item, dependent: :destroy

  after_create :set_permissions_to_owner
  after_create :handle_initial_publication
  before_save :check_public_status_change

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

  #  This function handles the initial publication. It checks if the item is public and publishes it to the marketplace if it is.
  def handle_initial_publication
    return unless is_public

    publish_to_marketplace
  end

  # Check public status change logic
  def check_public_status_change
    return unless is_public_changed?

    if is_public
      # if is_public changed from false to true, publish to marketplace
      publish_to_marketplace
    else
      # if is_public changed from true to false, unpublish from marketplace
      unpublish_from_marketplace
    end
  end

  # publish to marketplace
  def publish_to_marketplace
    marketplace_item = self.marketplace_item || build_marketplace_item
    marketplace_item.update(
      chatbot_id: id,
      user_id:,
      entity_name: Apartment::Tenant.current,
      chatbot_name: name,
      chatbot_description: description
    )
  end

  # unpublish from marketplace
  def unpublish_from_marketplace
    marketplace_item&.destroy
  end
end
