# frozen_string_literal: true

class AddUserMarketplaceItemToMessages < ActiveRecord::Migration[7.0]
  def change
    add_reference :messages, :user_marketplace_item, null: true, type: :uuid, index: true, optional: true
  end
end
