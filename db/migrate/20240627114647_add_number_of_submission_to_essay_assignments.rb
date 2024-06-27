class AddNumberOfSubmissionToEssayAssignments < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :number_of_submission, :integer, null: false, default: 0
  end
end
