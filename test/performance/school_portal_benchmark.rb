# frozen_string_literal: true
# rails runner test/performance/school_portal_benchmark.rb
# Uses only an explicitly isolated DB. Synthetic records and audit writes roll back.
raise 'Isolated test required' unless Rails.env.test? && ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
config = ActiveRecord::Base.connection_db_config
raise 'Unexpected DB' unless config.database == 'listening_rails_isolated_test' && %w[127.0.0.1 localhost].include?(config.configuration_hash[:host])
require 'action_dispatch/testing/integration'

many_grants = ENV['SCHOOL_BENCH_MANY_GRANTS'] == '1'
if ENV['SCHOOL_BENCH_LEGACY_GRANTS'] == '1'
  raise 'Legacy comparison is only for the isolated many-grants benchmark' unless many_grants
  # Original predicate, scoped to this benchmark process. Same exact year/class pairs.
  Api::School::V1::SchoolApiController.prepend(Module.new do
    private
    def students_scope
      scope = GeneralUser.joins(student_enrollments: :school_academic_year)
        .where(school_academic_years: { school_id: current_school.id }).distinct
      return scope unless current_general_user.school_password_manager?
      scope.where(student_enrollments: { id: authorized_student_enrollments.select(:id) })
        .where("general_users.meta->>'aienglish_role' = ?", 'student')
    end

    def authorized_student_enrollments
      scope = StudentEnrollment.joins(:school_academic_year)
        .where(school_academic_years: { school_id: current_school.id, status: SchoolAcademicYear.statuses[:active] })
        .where(status: StudentEnrollment.statuses[:active])
      current_general_user.school_password_grants.reduce(scope.none) do |allowed, grant|
        allowed.or(scope.where(school_academic_year_id: grant['school_academic_year_id'], class_name: grant['class_name']))
      end
    end
  end)
end

ActiveRecord::Base.transaction do
  now = Time.current
  school = School.create!(name: 'API benchmark', code: "bench-#{SecureRandom.hex(8)}", meta: {})
  years = 8.times.map do |index|
    SchoolAcademicYear.create!(school: school, name: "Bench #{index}", start_date: Date.new(2019 + index, 1, 1),
      end_date: Date.new(2019 + index, 12, 31), status: index == 7 ? :active : :archived, meta: {})
  end
  owner = GeneralUser.create!(email: "bench-#{SecureRandom.hex(8)}@example.test", nickname: 'Owner', password: 'LocalBenchmark123!', school: school,
    meta: { 'aienglish_role' => 'school_admin', 'aienglish_features_list' => [] }, konnecai_tokens: {})
  teacher_ids = 30.times.map { SecureRandom.uuid }
  student_ids = 400.times.map { SecureRandom.uuid }
  # Avoid callbacks/queues. These are synthetic read-only workload fixtures, not model validation examples.
  GeneralUser.insert_all!((teacher_ids + student_ids).map.with_index do |id, index|
    { id: id, nickname: "User #{index}", email: "#{id}@example.test", encrypted_password: '', created_at: now, updated_at: now,
      meta: { 'aienglish_role' => index < 30 ? 'teacher' : 'student', 'aienglish_features_list' => [] }, konnecai_tokens: {} }
  end)
  TeacherAssignment.insert_all!(years.flat_map { |year| teacher_ids.map { |id|
    { id: SecureRandom.uuid, general_user_id: id, school_academic_year_id: year.id, department: 'English', position: 'Teacher', status: 0, meta: {}, created_at: now, updated_at: now }
  } })
  StudentEnrollment.insert_all!(student_ids.map.with_index { |id, index|
    { id: SecureRandom.uuid, general_user_id: id, school_academic_year_id: years.last.id, class_name: "Class #{index % (many_grants ? 300 : 20)}", class_number: index.to_s, status: 0, meta: {}, created_at: now, updated_at: now }
  })
  assignment_ids = 30.times.map { SecureRandom.uuid }
  EssayAssignment.insert_all!(assignment_ids.map.with_index { |id, index|
    { id: id, general_user_id: teacher_ids[index], school_academic_year_id: years.last.id, title: "Benchmark #{index}", topic: 'Synthetic', assignment: 'Synthetic', code: SecureRandom.hex(8),
      category: EssayAssignment.categories['essay'], rubric: { 'name' => 'Benchmark' }, meta: {}, created_at: now + index, updated_at: now }
  })
  grading_payload = { 'data' => { 'text' => 'Synthetic benchmark detail. ' * 200 } }
  assignment_ids.each do |id|
    EssayGrading.insert_all!(200.times.map { |index|
      { id: SecureRandom.uuid, essay_assignment_id: id, general_user_id: student_ids[index], status: EssayGrading.statuses['draft'], essay: 'Synthetic essay. ' * 200,
        grading: grading_payload, general_context: {}, meta: {}, created_at: now + index, updated_at: now }
    })
  end
  token, = Warden::JWTAuth::UserEncoder.new.call(owner, :general_user, nil)
  headers = { 'Authorization' => "Bearer #{token}" }
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! 'localhost'
  paths = {
    me: ['/api/school/v1/me', {}],
    students: ['/api/school/v1/students', { school_academic_year_id: years.last.id }],
    teachers: ['/api/school/v1/teachers', { school_academic_year_id: years.last.id }],
    classes: ['/api/school/v1/academic_years', { include_classes: true }],
    assignments: ['/api/school/v1/assignments', {}],
    assignment_detail: ["/api/school/v1/assignments/#{assignment_ids.last}", {}],
    snapshot: ['/api/school/v1/snapshot', {}]
  }
  if many_grants
    teacher = GeneralUser.find(teacher_ids.first)
    teacher.update!(meta: teacher.meta.merge('school_password_access' => { 'school_id' => school.id,
      'enabled' => true, 'revision' => SecureRandom.uuid, 'session_version' => SecureRandom.uuid,
      'grants' => 300.times.map { |index| { 'school_academic_year_id' => years.last.id, 'class_name' => "Class #{index}" } } }))
    teacher.school_portal_login = true
    token, = Warden::JWTAuth::UserEncoder.new.call(teacher, :general_user, nil)
    headers = { 'Authorization' => "Bearer #{token}" }
    paths = paths.slice(:students, :classes)
  end
  results = {}
  paths.each do |name, (path, params)|
    session.get(path, params: params, headers: headers)
    raise "Warmup failed #{name}: #{session.response.status}" unless session.response.status == 200
    samples = 7.times.map do
      counts = Hash.new(0)
      queries = 0
      allocations = GC.stat(:total_allocated_objects)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      instantiated = ->(*args) { payload = args.last; counts[payload[:class_name]] += payload[:record_count] }
      sql = ->(*args) { payload = args.last; queries += 1 if !payload[:cached] && payload[:sql].start_with?('SELECT') }
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(instantiated, 'instantiation.active_record') do
          ActiveSupport::Notifications.subscribed(sql, 'sql.active_record') { session.get(path, params: params, headers: headers) }
        end
      end
      raise "Request failed #{name}: #{session.response.status}" unless session.response.status == 200
      { ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2), selects: queries,
        allocations: GC.stat(:total_allocated_objects) - allocations, records: counts }
    end
    sorted = samples.map { |row| row[:ms] }.sort
    results[name] = { median_ms: sorted[3], max_ms: sorted.last, first: samples.first }
  end
  puts JSON.pretty_generate({ fixture: { teachers: 30, students: 400, years: 8, assignments: 30, gradings: 6000 },
    samples_per_endpoint: 7, includes_network: false, many_grants: many_grants, legacy_grants: ENV['SCHOOL_BENCH_LEGACY_GRANTS'] == '1', results: results })
  raise ActiveRecord::Rollback
end
