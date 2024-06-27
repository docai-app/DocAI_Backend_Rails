class CreateEssayAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :essay_assignments, id: :uuid do |t|
      t.string :topic
      t.jsonb :rubric, null: false, default: {}
      t.string :code, null: false

      t.timestamps
    end
    add_index :essay_assignments, :code, unique: true

    add_reference :essay_gradings, :essay_assignment, type: :uuid, foreign_key: true, optional: true
  end
end
