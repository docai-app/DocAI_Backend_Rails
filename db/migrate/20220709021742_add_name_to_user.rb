# frozen_string_literal: true

class AddNameToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :name, :string
    add_column :users, :phone, :string
    add_column :users, :position, :string
    add_column :users, :date_of_birth, :date
    add_column :users, :sex, :integer
    add_column :users, :profile, :jsonb
  end
end
