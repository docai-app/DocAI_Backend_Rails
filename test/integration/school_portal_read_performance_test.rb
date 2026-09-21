# frozen_string_literal: true
raise 'Isolated test required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'

class SchoolPortalReadPerformanceTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    host! 'localhost'
    @school = School.create!(name: 'Read regression', code: SecureRandom.hex(8), meta: {})
    @year = SchoolAcademicYear.create!(school: @school, name: 'Current', start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year, status: :active, meta: {})
    @owner = user('school_admin', @school)
    @teacher = user('teacher')
    @student = user('student')
    TeacherAssignment.create!(general_user: @teacher, school_academic_year: @year, department: 'English', position: 'Teacher', status: :active, meta: {})
    @assignments = [45, 2, 0].map.with_index do |count, index|
      id = SecureRandom.uuid
      EssayAssignment.insert_all!([{ id: id, general_user_id: @teacher.id, school_academic_year_id: @year.id,
        topic: "Topic #{index}", title: "Assignment #{index}", assignment: 'Article', code: SecureRandom.hex(8), category: 0,
        rubric: { 'name' => 'Existing rubric' }, meta: { 'keep' => 'unchanged' }, created_at: Time.current + index, updated_at: Time.current }])
      # Do not enqueue grading workflows; these are read-path fixtures.
      EssayGrading.insert_all!(count.times.map { |n| { id: SecureRandom.uuid, essay_assignment_id: id,
        general_user_id: @student.id, status: EssayGrading.statuses['draft'], essay: 'Example',
        grading: { 'comprehension' => { 'score' => 80 } }, general_context: {}, meta: {},
        created_at: Time.current + n, updated_at: Time.current } }) if count.positive?
      EssayAssignment.find(id)
    end
    token, = Warden::JWTAuth::UserEncoder.new.call(@owner, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
  end

  test 'assignment list counts real submissions without hydrating student answers and preserves payload' do
    loaded = measure { get '/api/school/v1/assignments', headers: @headers, params: { per_page: 2 } }
    assert_response :success
    assert_equal 0, loaded['EssayGrading']
    rows = response.parsed_body.dig('data', 'assignments')
    assert_equal [@assignments[2].id, @assignments[1].id], rows.map { |row| row['id'] }
    assert_equal [0, 2], rows.map { |row| row['submissions_count'] }
    assert_equal({ 'keep' => 'unchanged' }, rows.first['meta'])
    assert_equal 'Article', rows.first['assignment']
    assert_equal @teacher.id, rows.first.dig('creator', 'id')
    assert_equal 3, response.parsed_body.dig('data', 'pagination', 'total_count')
    assert_equal 2, response.parsed_body.dig('data', 'pagination', 'total_pages')
    assert_equal 0, @assignments[0].number_of_submission, 'fixture deliberately has a stale counter cache'
  end

  test 'count sorting pagination and school creator isolation remain correct' do
    get '/api/school_admin/v1/assignments', headers: @headers, params: { sort_by: 'submissions_count', sort_order: 'desc', per_page: 2 }
    assert_response :success
    rows = response.parsed_body.dig('data', 'assignments')
    assert_equal [@assignments[0].id, @assignments[1].id], rows.map { |row| row['id'] }
    assert_equal [45, 2], rows.map { |row| row['submissions_count'] }
    assert_equal 3, response.parsed_body.dig('data', 'pagination', 'total_count')
    get '/api/school/v1/assignments', headers: @headers, params: { sort_by: 'submissions_count', page: 2, per_page: 2 }
    assert_response :success
    assert_equal [@assignments[2].id], response.parsed_body.dig('data', 'assignments').map { |row| row['id'] }
    get '/api/school/v1/assignments', headers: @headers, params: { creator_id: @student.id }
    assert_response :success
    assert_empty response.parsed_body.dig('data', 'assignments')
    get '/api/school/v1/assignments', headers: @headers, params: { creator_id: @teacher.id, search: 'Assignment 1', sort_by: 'creator' }
    assert_response :success
    assert_equal [@assignments[1].id], response.parsed_body.dig('data', 'assignments').map { |row| row['id'] }
  end

  test 'detail reads only ten recent submissions while keeping full statistics' do
    loaded = measure { get "/api/school/v1/assignments/#{@assignments[0].id}", headers: @headers }
    assert_response :success
    assert_equal 10, loaded['EssayGrading']
    stats = response.parsed_body.dig('data', 'assignment', 'statistics')
    assert_equal 45, stats['total_submissions']
    assert_equal({ 'draft' => 45 }, stats['submissions_stats'])
    assert_equal 10, stats['recent_submissions'].length
    assert stats['recent_submissions'].all? { |row| row['score'] == 80 }
  end

  test 'submissions page does not preload all answers before its pagination' do
    loaded = measure { get "/api/school/v1/assignments/#{@assignments[0].id}/submissions", headers: @headers, params: { per_page: 5 } }
    assert_response :success
    assert_operator loaded['EssayGrading'], :<=, 5
    assert_equal 5, response.parsed_body.dig('data', 'submissions').length
    assert_equal 45, response.parsed_body.dig('data', 'pagination', 'total_count')
  end

  test 'snapshot limits hydrated submissions to recent thirty while counting all submissions' do
    loaded = measure { get '/api/school/v1/snapshot', headers: @headers }
    assert_response :success
    assert_equal 30, loaded['EssayGrading']
    payload = response.parsed_body['data']
    assert_equal 3, payload.dig('counts', 'assignments')
    assert_equal 47, payload.dig('counts', 'recent_submissions')
    assert_equal [45, 2, 0], @assignments.map { |a| payload['assignments'].find { |row| row['id'] == a.id }['submissions_count'] }
    assert_equal 30, payload['submissions'].length
  end

  test 'a teacher shared by two schools cannot expose the other schools assignment or submission' do
    foreign_school = School.create!(name: 'Other read school', code: SecureRandom.hex(8), meta: {})
    foreign_year = SchoolAcademicYear.create!(school: foreign_school, name: 'Other current', start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year, status: :active, meta: {})
    TeacherAssignment.create!(general_user: @teacher, school_academic_year: foreign_year, department: 'English', position: 'Teacher', status: :active, meta: {})
    foreign_assignment = read_assignment(foreign_year.id)
    foreign_grading = SecureRandom.uuid
    EssayGrading.insert_all!([{ id: foreign_grading, essay_assignment_id: foreign_assignment,
      general_user_id: @student.id, status: EssayGrading.statuses['draft'], essay: 'Foreign private answer',
      grading: {}, general_context: {}, meta: {}, created_at: Time.current, updated_at: Time.current }])
    %w[school school_admin].each do |prefix|
      get "/api/#{prefix}/v1/assignments", headers: @headers
      assert_response :success
      refute_includes response.parsed_body.dig('data', 'assignments').map { |row| row['id'] }, foreign_assignment
      get "/api/#{prefix}/v1/assignments/#{foreign_assignment}", headers: @headers
      assert_response :not_found
      get "/api/#{prefix}/v1/assignments/#{foreign_assignment}/submissions", headers: @headers
      assert_response :not_found
      get "/api/#{prefix}/v1/submissions/#{foreign_grading}", headers: @headers
      assert_response :not_found
      get "/api/#{prefix}/v1/assignments/statistics", headers: @headers
      assert_response :success
      assert_equal 3, response.parsed_body.dig('data', 'total_assignments')
      assert_equal 47, response.parsed_body.dig('data', 'total_submissions')
      get "/api/#{prefix}/v1/snapshot", headers: @headers
      assert_response :success
      assert_equal 3, response.parsed_body.dig('data', 'counts', 'assignments')
      assert_equal 47, response.parsed_body.dig('data', 'counts', 'recent_submissions')
      refute_includes response.parsed_body.dig('data', 'submissions').map { |row| row['id'] }, foreign_grading
    end
  end

  test 'legacy assignments without a year require unambiguous school ownership' do
    legacy_assignment = read_assignment(nil)
    get '/api/school/v1/assignments', headers: @headers
    assert_response :success
    assert_includes response.parsed_body.dig('data', 'assignments').map { |row| row['id'] }, legacy_assignment
    other_school = School.create!(name: 'Other legacy school', code: SecureRandom.hex(8), meta: {})
    other_year = SchoolAcademicYear.create!(school: other_school, name: 'Other', start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year, status: :active, meta: {})
    TeacherAssignment.create!(general_user: @teacher, school_academic_year: other_year, department: 'English', position: 'Teacher', status: :active, meta: {})
    get '/api/school/v1/assignments', headers: @headers
    assert_response :success
    refute_includes response.parsed_body.dig('data', 'assignments').map { |row| row['id'] }, legacy_assignment
    get "/api/school/v1/assignments/#{legacy_assignment}", headers: @headers
    assert_response :not_found
  end

  test 'snapshot and audit log aliases redact historical credential metadata consistently' do
    SchoolAdminAuditLog.create!(actor_id: @owner.id, actor_role: 'school_admin', school_id: @school.id,
      action: 'student_password_reset', metadata: { 'password' => 'synthetic-private-password',
        'password_confirmation' => 'synthetic-private-confirmation', 'default_password_label' => 'synthetic-private-default',
        'reset_to_default_password' => true }, created_at: Time.current)
    %w[school school_admin].each do |prefix|
      %w[snapshot audit_logs].each do |endpoint|
        get "/api/#{prefix}/v1/#{endpoint}", headers: @headers
        assert_response :success
        refute_includes response.body, 'synthetic-private-'
        assert_equal true, response.parsed_body.dig('data', 'logs').first.dig('metadata', 'reset_to_default_password')
      end
    end
  end

  private

  def read_assignment(year_id)
    id = SecureRandom.uuid
    EssayAssignment.insert_all!([{ id: id, general_user_id: @teacher.id, school_academic_year_id: year_id,
      topic: 'Scope regression', title: 'Scope regression', assignment: 'Article', code: SecureRandom.hex(8), category: 0,
      rubric: {}, meta: {}, created_at: Time.current, updated_at: Time.current }])
    id
  end

  def user(role, school = nil)
    GeneralUser.create!(email: "read-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', nickname: role,
      school: school, meta: { 'aienglish_role' => role, 'aienglish_features_list' => [] }, konnecai_tokens: {})
  end

  def measure
    records = Hash.new(0)
    collect = ->(*args) { payload = args.last; records[payload[:class_name]] += payload[:record_count] }
    ActiveSupport::Notifications.subscribed(collect, 'instantiation.active_record') { yield }
    records
  end
end
