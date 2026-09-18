# frozen_string_literal: true

raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'

class SchoolPasswordDelegationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    host! 'localhost'
    @school = School.create!(name: 'Delegation test', code: SecureRandom.hex(6), meta: {})
    @year = year(@school)
    @owner = user('school_admin', @school)
    @manager = user('school_password_manager', @school)
    @manager.update!(meta: @manager.meta.merge('school_password_access' => {
      'enabled' => true, 'grants' => [grant(@year, '1A')], 'revision' => SecureRandom.uuid,
      'session_version' => SecureRandom.uuid
    }))
    @student = student(@year, '1A')
    @other_class = student(@year, '1AB')
  end

  test 'create account and reject cross school or unknown grants without partial writes' do
    post '/api/school_admin/v1/password_managers', headers: headers(@owner), as: :json,
      params: { email: "new-#{SecureRandom.hex(5)}@example.test", nickname: 'Teacher A', password: 'Password123!', grants: [grant(@year, '1A')] }
    assert_response :created
    created = GeneralUser.find(response.parsed_body.dig('data', 'account', 'id'))
    assert_equal 'school_password_manager', created.aienglish_role
    assert_equal @school.id, created.school_id
    assert_equal 1, created.school_password_grants.length
    refute_includes response.body, 'Password123!'
    before = GeneralUser.count
    post '/api/school/v1/password_managers', headers: headers(@owner), as: :json,
      params: { email: "bad-#{SecureRandom.hex(5)}@example.test", nickname: 'Bad', password: 'Password123!', grants: [grant(@year, 'missing')] }
    assert_response :unprocessable_entity
    assert_equal before, GeneralUser.count
  end

  test 'login supports manager and keeps current owner behavior' do
    [@owner, @manager].each do |actor|
      reset!
      host! 'localhost'
      post '/api/school_admin/v1/session', as: :json, params: { email: actor.email, password: 'Password123!' }
      assert_response :success
      assert_includes response.parsed_body.dig('data', 'user', 'capabilities'), 'passwords'
      get '/api/school_admin/v1/me', headers: { 'Authorization' => response.headers['Authorization'] }
      assert_response :success
    end
  end

  test 'explicit school login can switch from a previous manager cookie to the owner' do
    post '/api/school_admin/v1/session', as: :json, params: { email: @manager.email, password: 'Password123!' }
    assert_response :success
    post '/api/school_admin/v1/session', as: :json, params: { email: @owner.email, password: 'Password123!' }
    assert_response :success
    assert_equal @owner.id, response.parsed_body.dig('data', 'user', 'id')
  end

  test 'both aliases only expose exact authorized class and permit its password reset' do
    %w[school school_admin].each do |prefix|
      get "/api/#{prefix}/v1/students", headers: headers(@manager), params: { school_academic_year_id: @year.id, class_name: '1' }
      assert_response :success
      assert_equal [@student.id], response.parsed_body.dig('data', 'students').map { |s| s['id'] }
      assert_equal 'no-store', response.headers['Cache-Control']
      post "/api/#{prefix}/v1/students/#{@other_class.id}/reset_password", headers: headers(@manager), as: :json
      assert_response :not_found
      post "/api/#{prefix}/v1/students/#{@student.id}/reset_password", headers: headers(@manager), as: :json
      assert_response :success
      assert @student.reload.valid_password?(SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD)
    end
    logs = SchoolAdminAuditLog.where(actor_id: @manager.id, action: 'student_password_reset')
    assert_equal 2, logs.count
    assert_equal 'school_password_manager', logs.last.actor_role
    refute_includes logs.last.metadata.to_json, SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD
  end

  test 'other schools and same named classes in different years never match' do
    second_year = year(@school)
    other = student(second_year, '1A')
    foreign_school = School.create!(name: 'Other', code: SecureRandom.hex(6), meta: {})
    foreign_year = year(foreign_school)
    foreign = student(foreign_year, '1A')
    [other, foreign].each do |target|
      get "/api/school/v1/students/#{target.id}", headers: headers(@manager)
      assert_response :not_found
      post "/api/school/v1/students/#{target.id}/reset_password", headers: headers(@manager), as: :json
      assert_response :not_found
    end
    get '/api/school/v1/students', headers: headers(@manager), params: { school_academic_year_id: second_year.id }
    assert_response :success
    assert_empty response.parsed_body.dig('data', 'students')
    post '/api/school/v1/password_managers', headers: headers(@owner), as: :json,
      params: { email: "bad-#{SecureRandom.hex(5)}@example.test", nickname: 'Bad', password: 'Password123!', grants: [grant(foreign_year, '1A')] }
    assert_response :unprocessable_entity
  end

  test 'no grants and historical enrollment do not fall back to full school scope' do
    @manager.update!(meta: @manager.meta.deep_merge('school_password_access' => { 'grants' => [] }))
    get '/api/school/v1/students', headers: headers(@manager)
    assert_response :success
    assert_empty response.parsed_body.dig('data', 'students')
    @manager.update!(meta: @manager.meta.deep_merge('school_password_access' => { 'grants' => [grant(@year, '1A')] }))
    @student.student_enrollments.update_all(status: StudentEnrollment.statuses[:promoted])
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: headers(@manager), as: :json
    assert_response :not_found
  end

  test 'moved student loses access and arbitrary detail year cannot expose a different enrollment' do
    other_year = year(@school)
    StudentEnrollment.create!(general_user: @student, school_academic_year: other_year, class_name: 'SECRET', class_number: '9', status: :active, meta: {})
    get "/api/school/v1/students/#{@student.id}", headers: headers(@manager), params: { school_academic_year_id: other_year.id }
    assert_response :not_found
    @student.student_enrollments.find_by!(school_academic_year: @year).update!(class_name: '1B')
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: headers(@manager), as: :json
    assert_response :not_found
  end

  test 'revocation applies to an already issued token and stale edits return conflict' do
    token_headers = headers(@manager)
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], grants: [] }
    assert_response :success
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], grants: [grant(@year, '1A')] }
    assert_response :conflict
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: token_headers, as: :json
    assert_response :not_found
  end

  test 'disable and reenable never reactivate previous tokens' do
    old_headers = headers(@manager)
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], enabled: false }
    assert_response :success
    get '/api/school/v1/me', headers: old_headers
    assert_includes [401, 403], response.status
    reset!
    host! 'localhost'
    post '/api/school/v1/session', as: :json, params: { email: @manager.email, password: 'Password123!' }
    assert_response :unauthorized
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.reload.school_password_access['revision'], enabled: true }
    assert_response :success
    get '/api/school/v1/me', headers: old_headers
    assert_response :forbidden
    get '/api/school/v1/me', headers: headers(@manager.reload)
    assert_response :success
  end

  test 'new password invalidates an already issued token and rejects short replacements' do
    old_headers = headers(@manager)
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], password: 'short' }
    assert_response :unprocessable_entity
    assert @manager.reload.valid_password?('Password123!')
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], password: 'ChangedPassword123!' }
    assert_response :success
    get '/api/school/v1/me', headers: old_headers
    assert_response :forbidden
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: old_headers, as: :json
    assert_response :forbidden
    assert @manager.reload.valid_password?('ChangedPassword123!')
  end

  test 'manager cannot access other portal features generic APIs or account management' do
    %w[snapshot teachers assignments audit_logs password_managers password_managers/classes].each do |path|
      get "/api/school/v1/#{path}", headers: headers(@manager)
      assert_response :forbidden
    end
    get '/api/v1/essay_assignments', headers: headers(@manager)
    assert_response :forbidden
    post '/api/school/v1/password_managers', headers: headers(@manager), as: :json, params: {}
    assert_response :forbidden
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@manager), as: :json,
      params: { enabled: true, grants: [grant(@year, '1AB')], meta: { aienglish_role: 'school_admin' } }
    assert_response :forbidden
    assert_equal 'school_password_manager', @manager.reload.aienglish_role
  end

  test 'owner account update cannot promote or move manager to a different school' do
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], school_id: SecureRandom.uuid,
                meta: { aienglish_role: 'school_admin' }, role: 'school_admin', nickname: 'Renamed' }
    assert_response :success
    assert_equal @school.id, @manager.reload.school_id
    assert_equal 'school_password_manager', @manager.aienglish_role
    assert_equal 'Renamed', @manager.nickname
    get '/api/school/v1/students', headers: headers(@owner), params: { school_academic_year_id: @year.id }
    assert_response :success
    assert_equal 2, response.parsed_body.dig('data', 'students').size
  end

  private

  def year(school)
    SchoolAcademicYear.create!(school: school, name: SecureRandom.hex(4), start_date: Date.current.beginning_of_year + school.school_academic_years.count.years,
      end_date: Date.current.end_of_year + school.school_academic_years.count.years, status: :active, meta: {})
  end

  def user(role, school = nil)
    GeneralUser.create!(email: "delegation-#{SecureRandom.hex(6)}@example.test", password: 'Password123!',
      nickname: role, school: school, meta: { 'aienglish_role' => role, 'aienglish_features_list' => [] }, konnecai_tokens: {})
  end

  def student(year, klass)
    user('student').tap do |u|
      StudentEnrollment.create!(general_user: u, school_academic_year: year, class_name: klass, class_number: '1', status: :active, meta: {})
    end
  end

  def grant(year, klass)
    { 'school_academic_year_id' => year.id, 'class_name' => klass }
  end

  def headers(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    { 'Authorization' => "Bearer #{token}" }
  end
end
