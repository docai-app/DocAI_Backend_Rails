# frozen_string_literal: true

class UpdateChatbotsDefaultEnergyCost20 < ActiveRecord::Migration[7.0]
  def change
    change_column_default :chatbots, :energy_cost, 0
  end
end
