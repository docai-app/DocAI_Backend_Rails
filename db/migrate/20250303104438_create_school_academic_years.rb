# frozen_string_literal: true

class CreateSchoolAcademicYears < ActiveRecord::Migration[7.0]
  def change
    create_table :school_academic_years, id: :uuid do |t|
      t.references :school, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :status, default: 0
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
  end
end
