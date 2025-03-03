# frozen_string_literal: true

class AddKonnecAiTokensToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :konnecai_tokens, :jsonb, null: false, default: {}
  end
end
