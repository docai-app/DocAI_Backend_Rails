class AddScoreAndQuestionsCountToAssessmentRecord < ActiveRecord::Migration[7.0]
  def change
    add_column :assessment_records, :score, :decimal, null: false, default: 0
    add_column :assessment_records, :questions_count, :integer, null: false, default: 0
    add_column :assessment_records, :full_score, :decimal, default: 0, null: false
  end
end
