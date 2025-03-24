# frozen_string_literal: true

class CreateTeacherAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :teacher_assignments, id: :uuid do |t|
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: false, foreign_key: true, type: :uuid
      t.string :department
      t.string :position
      t.integer :status
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
  end
end
