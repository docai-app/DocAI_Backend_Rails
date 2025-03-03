# frozen_string_literal: true

class AddRemarkToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :remark, :string
  end
end
