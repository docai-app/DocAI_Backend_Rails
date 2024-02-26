# frozen_string_literal: true

# == Schema Information
#
# Table name: public.user_marketplace_items
#
#  id                  :uuid             not null, primary key
#  user_type           :string           not null
#  user_id             :uuid             not null
#  marketplace_item_id :uuid             not null
#  custom_name         :string
#  custom_description  :text
#  purchase_id         :uuid             not null
#  meta                :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_user_marketplace_items_on_marketplace_item_id  (marketplace_item_id)
#  index_user_marketplace_items_on_purchase_id          (purchase_id)
#  index_user_marketplace_items_on_user                 (user_type,user_id)
#
# Foreign Keys
#
#  fk_rails_...  (marketplace_item_id => marketplace_items.id)
#  fk_rails_...  (purchase_id => purchases.id)
#
class UserMarketplaceItem < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :marketplace_item
  belongs_to :purchase
  has_many :messages, dependent: :destroy

  def save_message(role, object_type, content, meta = {})
    messages.create!(
      chatbot_id: marketplace_item.chatbot_id,
      role:,
      object_type:,
      content:,
      meta:
    )
  end

  def get_chatbot_messages(user_id)
    puts "Get chatbot messages: #{user_id}"
    messages.where("meta->>'belongs_user_id' = ?", user_id).order(created_at: :desc)
  end
end
