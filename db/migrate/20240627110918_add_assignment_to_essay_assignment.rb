# frozen_string_literal: true

class AddAssignmentToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :assignment, :string
  end
end
