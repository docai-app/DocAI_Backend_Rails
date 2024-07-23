# frozen_string_literal: true

class AddTimezoneOnTheGeneralUserTable < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :timezone, :string, default: 'Asia/Hong_Kong', null: false
  end
end
