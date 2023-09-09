# frozen_string_literal: true

class AddIsPublicToTheChatbots < ActiveRecord::Migration[7.0]
  def change
    add_column :chatbots, :is_public, :boolean, default: false, index: true, null: false
    add_column :chatbots, :expired_at, :datetime, index: true, null: true, default: nil
    add_column :chatbots, :access_count, :integer, default: 0
  end
end
