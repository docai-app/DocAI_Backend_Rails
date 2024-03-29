# frozen_string_literal: true

class CreateDepartments < ActiveRecord::Migration[7.0]
  def change
    create_table :departments do |t|
      t.string :name
      t.string :description
      t.jsonb :meta

      t.timestamps
    end
  end
end
