# frozen_string_literal: true

class CreateStudentEnrollments < ActiveRecord::Migration[7.0]
  def change
    create_table :student_enrollments, id: :uuid do |t|
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: false, foreign_key: true, type: :uuid
      t.string :class_name
      t.string :class_number
      t.integer :status
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
  end
end
