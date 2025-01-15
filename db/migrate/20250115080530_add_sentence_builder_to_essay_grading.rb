class AddSentenceBuilderToEssayGrading < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_gradings, :sentence_builder, :jsonb
  end
end
