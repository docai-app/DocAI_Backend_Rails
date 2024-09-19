# frozen_string_literal: true

class AddWhatsAppNumberColumn2GeneralUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :whats_app_number, :string, unique: true
  end
end
