# frozen_string_literal: true

class AddEnergyCostToChatbots < ActiveRecord::Migration[7.0]
  def change
    add_column :chatbots, :energy_cost, :integer, default: 1
  end
end
