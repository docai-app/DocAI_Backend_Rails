# frozen_string_literal: true

# Run with rails runner, never against development/production data.
raise 'Isolated test environment required' unless Rails.env.test? && ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
raise 'Unexpected database' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'listening_rails_isolated_test'

ActiveRecord::Base.transaction do
  %w[teacher student].each do |role|
    email = "listening-http-#{role}@example.test"
    existing = GeneralUser.find_by(email: email)
    if existing
      raise 'Refusing to change an unrelated account' unless existing.meta['listening_http_fixture'] == true
      next
    end
    GeneralUser.create!(email: email, password: 'ListeningLocalTest123!', nickname: "Listening HTTP #{role}",
      meta: { 'listening_http_fixture' => true, 'aienglish_role' => role,
        'aienglish_features_list' => ['listening'] }, konnecai_tokens: {})
  end
  school = School.find_or_initialize_by(code: 'listening-http-local')
  if school.persisted?
    raise 'Refusing to reuse unrelated school' unless school.meta['listening_http_fixture'] == true
  else
    school.assign_attributes(name: 'Listening HTTP Test School', timezone: 'Asia/Hong_Kong',
      meta: { 'listening_http_fixture' => true })
    school.save!
  end
  year = SchoolAcademicYear.find_or_create_by!(school: school, name: "Listening HTTP #{Date.current.year}") do |row|
    row.start_date = Date.current.beginning_of_year
    row.end_date = Date.current.end_of_year
    row.status = :active
  end
  teacher = GeneralUser.find_by!(email: 'listening-http-teacher@example.test')
  student = GeneralUser.find_by!(email: 'listening-http-student@example.test')
  TeacherAssignment.find_or_create_by!(general_user: teacher, school_academic_year: year) do |row|
    row.department = 'English'
    row.position = 'Teacher'
    row.status = :active
    row.meta = { 'listening_http_fixture' => true }
  end
  StudentEnrollment.find_or_create_by!(general_user: student, school_academic_year: year) do |row|
    row.class_name = 'Listening A1'
    row.class_number = '1'
    row.status = :active
    row.meta = { 'listening_http_fixture' => true }
  end
end
puts 'Isolated Listening HTTP teacher/student school memberships ready; existing records were not overwritten.'
