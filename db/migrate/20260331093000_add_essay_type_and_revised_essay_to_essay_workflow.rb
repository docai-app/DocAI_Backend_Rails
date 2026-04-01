# frozen_string_literal: true

class AddEssayTypeAndRevisedEssayToEssayWorkflow < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :essay_type, :string
    add_column :essay_gradings, :revised_essay, :jsonb, null: false, default: {}
  end
end
