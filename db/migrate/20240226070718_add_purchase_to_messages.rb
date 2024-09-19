# frozen_string_literal: true

class AddPurchaseToMessages < ActiveRecord::Migration[7.0]
  def change
    add_reference :messages, :purchase, null: true, foreign_key: true, type: :uuid, index: true, optional: true
  end
end
