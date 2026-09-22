# frozen_string_literal: true
raise 'Isolated test required' unless Rails.env.test? && ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
raise 'Unexpected DB' unless ActiveRecord::Base.connection_db_config.database == 'listening_rails_isolated_test'

school = School.find_or_create_by!(code: 'school-password-browser-fixture') { |s| s.name = '測試學校'; s.meta = {} }
year = school.school_academic_years.find_or_create_by!(name: '2026–2027') do |y|
  y.start_date = Date.new(2026, 9, 1); y.end_date = Date.new(2027, 8, 31); y.status = :active; y.meta = {}
end
owner = GeneralUser.find_or_initialize_by(email: 'school-owner@delegation.example.test')
owner.assign_attributes(nickname: '測試學校管理員', school: school, password: 'LocalBrowser123!',
  meta: { 'aienglish_role' => 'school_admin', 'aienglish_features_list' => [] }, konnecai_tokens: {})
owner.save!
%w[1A 1B 2A].each do |klass|
  student = GeneralUser.find_or_initialize_by(email: "student-#{klass.downcase}@delegation.example.test")
  student.assign_attributes(nickname: "#{klass} 測試學生", password: 'LocalBrowser123!',
    meta: { 'aienglish_role' => 'student', 'aienglish_features_list' => [] }, konnecai_tokens: {})
  student.save!
  StudentEnrollment.find_or_create_by!(general_user: student, school_academic_year: year) do |e|
    e.class_name = klass; e.class_number = '1'; e.status = :active; e.meta = {}
  end
end
# Existing teaching accounts, including enough rows to exercise picker pagination.
24.times do |index|
  email = index.zero? ? 'teacher-existing@delegation.example.test' : "teacher-picker-#{index.to_s.rjust(2, '0')}@delegation.example.test"
  teacher = GeneralUser.find_or_initialize_by(email: email)
  teacher.assign_attributes(nickname: index.zero? ? '授權測試老師' : "名單測試老師 #{index.to_s.rjust(2, '0')}",
    password: 'LocalTeacher123!', meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => ['essay'] }, konnecai_tokens: {})
  teacher.save!
  TeacherAssignment.find_or_create_by!(general_user: teacher, school_academic_year: year) do |assignment|
    assignment.department = 'English'; assignment.position = 'Teacher'; assignment.status = :active; assignment.meta = {}
  end
end
puts 'Synthetic school browser fixture ready.'
