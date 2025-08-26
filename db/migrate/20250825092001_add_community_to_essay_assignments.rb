# frozen_string_literal: true

class AddCommunityToEssayAssignments < ActiveRecord::Migration[7.0]
  def change
    add_reference :essay_assignments, :community, type: :uuid, foreign_key: true, null: true
  end
end