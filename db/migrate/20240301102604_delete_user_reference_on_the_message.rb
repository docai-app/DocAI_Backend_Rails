# frozen_string_literal: true

class DeleteUserReferenceOnTheMessage < ActiveRecord::Migration[7.0]
  def change
    remove_reference :messages, :user, index: true, foreign_key: true, type: :uuid
  end
end
