# frozen_string_literal: true

class AddUserPolymorphicToMessage < ActiveRecord::Migration[7.0]
  def change
    remove_column :messages, :user_type, :string
    add_reference :messages, :user, polymorphic: true, type: :uuid, index: true, null: true
  end
end
