# frozen_string_literal: true

class AddScoreToEssayGrading < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_gradings, :score, :decimal
  end
end
