class CreateStudentSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :student_snapshots do |t|
      t.string :nickname
      t.string :class_name
      t.string :class_no
      t.uuid :school_id
      t.string :academic_year
      t.string :semester
      t.uuid :general_user_id

      t.timestamps
    end
  end
end
