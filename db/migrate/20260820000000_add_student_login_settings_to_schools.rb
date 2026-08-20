# frozen_string_literal: true

# Adds the public school sign-in slug and fixed student email domain settings.
class AddStudentLoginSettingsToSchools < ActiveRecord::Migration[7.0]
  def change
    add_column :schools, :student_login_enabled, :boolean, default: false, null: false
    add_column :schools, :student_login_slug, :string
    add_column :schools, :student_email_domain, :string

    add_index :schools,
              :student_login_slug,
              unique: true,
              where: 'student_login_slug IS NOT NULL',
              name: 'index_schools_on_student_login_slug'
  end
end
