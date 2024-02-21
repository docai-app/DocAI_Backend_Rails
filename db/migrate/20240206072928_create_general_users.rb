# frozen_string_literal: true

class CreateGeneralUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :general_users, id: :uuid do |t|
      t.string :email
      t.string :encrypted_password
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.string :nickname
      t.string :phone
      t.date :date_of_birth
      t.integer :sex

      t.timestamps
    end
    add_index :general_users, :email, unique: true
  end
end
