# frozen_string_literal: true

# == Schema Information
#
# Table name: marketplace_items
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
class MarketplaceItem < ApplicationRecord
  belongs_to :chatbot
  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'

  # Add validation to ensure data is complete
  validates :chatbot_id, presence: true
  validates :entity_name, presence: true
end
