# frozen_string_literal: true

class UserMarketplaceItem < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :marketplace_item
  belongs_to :purchase
end
