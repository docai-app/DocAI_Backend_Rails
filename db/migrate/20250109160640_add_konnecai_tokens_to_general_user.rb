# frozen_string_literal: true

class AddKonnecaiTokensToGeneralUser < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :konnecai_tokens, :jsonb, null: false, default: {}
  end
end
