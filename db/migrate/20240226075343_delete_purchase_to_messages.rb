# frozen_string_literal: true

class DeletePurchaseToMessages < ActiveRecord::Migration[7.0]
  def change
    remove_reference :messages, :purchase, index: true, foreign_key: true
    remove_column :purchases, :custom_name, :string
    remove_column :purchases, :custom_description, :string
  end
end
