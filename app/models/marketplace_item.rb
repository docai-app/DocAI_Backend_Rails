# frozen_string_literal: true

# == Schema Information
#
# Table name: public.marketplace_items
#
#  id                  :uuid             not null, primary key
#  chatbot_id          :uuid
#  user_id             :uuid
#  entity_name         :string           not null
#  chatbot_name        :string           not null
#  chatbot_description :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_marketplace_items_on_entity_name  (entity_name)
#
class MarketplaceItem < ApplicationRecord
  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'

  has_many :purchases, dependent: :destroy
  has_many :purchasers, through: :purchases, source: :user

  # Add validation to ensure data is complete
  validates :chatbot_id, presence: true
  validates :entity_name, presence: true

  def purchase_by(user, custom_name = nil, custom_description = nil)
    # Implement purchase logic, such as creating a Purchase record
    Purchase.create(user:, marketplace_item: self, purchased_at: Time.current, custom_name:,
                    custom_description:)
  end
end
