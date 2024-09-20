class AddAnswerVisibleToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :answer_visible, :boolean, default: true, null: false
  end
end
