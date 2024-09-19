# frozen_string_literal: true

class AddUserTypeToTheDagRun < ActiveRecord::Migration[7.0]
  def change
    add_column :dag_runs, :user_type, :string, null: false, default: 'User'
  end
end
