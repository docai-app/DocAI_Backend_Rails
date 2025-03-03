# frozen_string_literal: true

class AddSubmissionClassInfoToEssayGradings < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_gradings, :submission_class_name, :string
    add_column :essay_gradings, :submission_class_number, :string
    add_column :essay_gradings, :submission_school_id, :uuid
    add_column :essay_gradings, :submission_academic_year_id, :uuid
  end
end
