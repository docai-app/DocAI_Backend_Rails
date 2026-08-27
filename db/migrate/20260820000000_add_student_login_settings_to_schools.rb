# frozen_string_literal: true

# schools 表在各 tenant schema；public 若无 schools 则跳过。
class AddStudentLoginSettingsToSchools < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_schools_on_student_login_slug'

  def up
    return unless table_exists?(:schools)
    return if column_exists?(:schools, :student_login_enabled)

    add_column :schools, :student_login_enabled, :boolean, default: false, null: false
    add_column :schools, :student_login_slug, :string
    add_column :schools, :student_email_domain, :string

    return if index_exists?(:schools, :student_login_slug, name: INDEX_NAME)

    add_index :schools,
              :student_login_slug,
              unique: true,
              where: 'student_login_slug IS NOT NULL',
              name: INDEX_NAME
  end

  def down
    return unless table_exists?(:schools)

    remove_index :schools, name: INDEX_NAME, if_exists: true
    remove_column :schools, :student_email_domain, if_exists: true
    remove_column :schools, :student_login_slug, if_exists: true
    remove_column :schools, :student_login_enabled, if_exists: true
  end
end
