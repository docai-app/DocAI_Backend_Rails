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

  test 'school credentials accept existing plus-address emails' do
    @owner.update!(email: "owner+#{SecureRandom.hex(8)}@example.test")
    post '/api/school_admin/v1/session', as: :json, params: { email: @owner.email, password: 'Password123!' }
    assert_response :success
    assert_equal @owner.id, response.parsed_body.dig('data', 'user', 'id')
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

  test 'password reset unlocks students for owners and managers through both aliases' do
    [@owner, @manager].each do |actor|
      %w[school school_admin].each do |prefix|
        @student.update!(password: 'BeforeReset123!', locked_at: Time.current,
          failed_attempts: 20, unlock_token: SecureRandom.hex(16))
        assert @student.access_locked?
        post "/api/#{prefix}/v1/students/#{@student.id}/reset_password", headers: headers(actor), as: :json,
          params: { school_academic_year_id: @year.id }
        assert_response :success
        @student.reload
        assert @student.valid_password?(SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD)
        refute @student.valid_password?('BeforeReset123!')
        assert_nil @student.locked_at
        assert_nil @student.unlock_token
        assert_equal 0, @student.failed_attempts
        refute @student.access_locked?
        log = SchoolAdminAuditLog.where(actor_id: actor.id, target_id: @student.id, action: 'student_password_reset').order(:created_at).last
        assert_equal true, log.metadata['account_unlocked']
        refute_includes log.metadata.to_json, SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD

        reset!
        host! 'localhost'
        post '/general_users/sign_in.json', as: :json,
          params: { general_user: { email: @student.email, password: SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD } }
        assert_response :success
        reset!
        host! 'localhost'
      end
    end
  end

  test 'linked teacher portal can reset and unlock only an authorized class' do
    teacher = employed_teacher(@year)
    post '/api/school_admin/v1/password_managers', headers: headers(@owner), as: :json,
      params: { teacher_id: teacher.id, grants: [grant(@year, '1A')] }
    assert_response :created
    post '/api/school_admin/v1/session', as: :json,
      params: { email: teacher.email, password: 'Password123!' }
    assert_response :success
    portal_headers = { 'Authorization' => response.headers['Authorization'] }
    [@student, @other_class].each do |target|
      target.update!(locked_at: Time.current, failed_attempts: 20, unlock_token: SecureRandom.hex(16))
    end
    denied_before = @other_class.reload.attributes.slice('encrypted_password', 'locked_at', 'failed_attempts', 'unlock_token')
    post "/api/school_admin/v1/students/#{@other_class.id}/reset_password", headers: portal_headers, as: :json,
      params: { school_academic_year_id: @year.id }
    assert_response :not_found
    assert_equal denied_before, @other_class.reload.attributes.slice(*denied_before.keys)
    post "/api/school_admin/v1/students/#{@student.id}/reset_password", headers: portal_headers, as: :json,
      params: { school_academic_year_id: @year.id }
    assert_response :success
    assert @student.reload.valid_password?(SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD)
    assert_nil @student.locked_at
    assert_nil @student.unlock_token
    assert_equal 0, @student.failed_attempts
    assert_equal 'teacher', teacher.reload.aienglish_role
    assert teacher.valid_password?('Password123!')
  end

  test 'reset clears failed attempts on an unlocked student too' do
    @student.update!(failed_attempts: 3, unlock_token: SecureRandom.hex(16))
    post "/api/school_admin/v1/students/#{@student.id}/reset_password", headers: headers(@manager), as: :json
    assert_response :success
    assert_equal 0, @student.reload.failed_attempts
    assert_nil @student.locked_at
    assert_nil @student.unlock_token
    assert @student.valid_password?(SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD)
    log = SchoolAdminAuditLog.find_by!(target_id: @student.id, action: 'student_password_reset')
    assert_equal false, log.metadata['account_unlocked']
  end

  test 'failed reset validation preserves both the original password and lock' do
    @student.update!(locked_at: Time.current, failed_attempts: 20, unlock_token: SecureRandom.hex(16))
    # A legacy invalid record must not be unlocked when the password cannot save.
    @student.update_column(:email, '')
    before = @student.reload.attributes.slice('encrypted_password', 'locked_at', 'failed_attempts', 'unlock_token')
    assert_no_difference 'SchoolAdminAuditLog.count' do
      post "/api/school_admin/v1/students/#{@student.id}/reset_password", headers: headers(@manager), as: :json
    end
    assert_response :unprocessable_entity
    assert_equal before, @student.reload.attributes.slice(*before.keys)
  end

  test 'denied resets never change lock state in other classes years or schools' do
    other_year = year(@school)
    foreign_school = School.create!(name: 'Locked outside school', code: SecureRandom.hex(6), meta: {})
    targets = [@other_class, student(other_year, '1A'), student(year(foreign_school), '1A')]
    targets.each do |target|
      target.update!(locked_at: Time.current, failed_attempts: 20, unlock_token: SecureRandom.hex(16))
      before = target.reload.attributes.slice('encrypted_password', 'locked_at', 'failed_attempts', 'unlock_token')
      %w[school school_admin].each do |prefix|
        assert_no_difference 'SchoolAdminAuditLog.count' do
          post "/api/#{prefix}/v1/students/#{target.id}/reset_password", headers: headers(@manager), as: :json,
            params: { school_academic_year_id: @year.id }
        end
        assert_response :not_found
        assert_equal before, target.reload.attributes.slice(*before.keys)
      end
    end
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

  test 'owner deletes only a local delegated account and old sessions cannot return' do
    old_headers = headers(@manager)
    revision = @manager.school_password_access['revision']
    before_count = GeneralUser.count
    delete "/api/school_admin/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: revision }
    assert_response :no_content
    assert_equal before_count, GeneralUser.count
    assert @manager.reload.school_password_access['deleted_at'].present?
    assert_empty @manager.school_password_grants
    refute @manager.active_for_authentication?
    get '/api/school/v1/password_managers', headers: headers(@owner)
    assert_response :success
    refute_includes response.parsed_body.dig('data', 'accounts').map { |account| account['id'] }, @manager.id
    get '/api/school/v1/me', headers: old_headers
    assert_includes [401, 403], response.status
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: old_headers, as: :json
    assert_includes [401, 403], response.status
    patch "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: @manager.school_password_access['revision'], enabled: true }
    assert_response :not_found
    delete "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: revision }
    assert_response :no_content
    assert_equal 1, SchoolAdminAuditLog.where(target_id: @manager.id, action: 'password_manager_deleted').count
    reset!
    host! 'localhost'
    post '/api/school/v1/session', as: :json, params: { email: @manager.email, password: 'Password123!' }
    assert_response :unauthorized
  end

  test 'delete rejects delegated actors protected owner foreign school and stale revisions' do
    delete "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@manager), as: :json
    assert_response :forbidden
    delete "/api/school/v1/password_managers/#{@owner.id}", headers: headers(@owner), as: :json
    assert_response :not_found
    foreign = School.create!(name: 'Foreign', code: SecureRandom.hex(6), meta: {})
    foreign_manager = user('school_password_manager', foreign)
    delete "/api/school/v1/password_managers/#{foreign_manager.id}", headers: headers(@owner), as: :json
    assert_response :not_found
    delete "/api/school/v1/password_managers/#{@manager.id}", headers: headers(@owner), as: :json,
      params: { revision: 'stale' }
    assert_response :conflict
    assert @manager.reload.portal_password_manager?
    assert_equal 0, SchoolAdminAuditLog.where(school_id: @school.id, action: 'password_manager_deleted').count
  end

  test 'class dropdown contains only current authorized exact enrollment classes' do
    old_year = year(@school)
    student(old_year, 'OLD')
    old_year.update!(status: :archived)
    @manager.update!(meta: @manager.meta.deep_merge('school_password_access' => {
      'grants' => [grant(@year, '1A'), grant(old_year, 'OLD')]
    }))
    get '/api/school_admin/v1/academic_years', headers: headers(@manager), params: { include_classes: 'true' }
    assert_response :success
    years = response.parsed_body.dig('data', 'academic_years')
    assert_equal [@year.id], years.map { |row| row['id'] }
    assert_equal ['1A'], years.first['classes']
    get '/api/school/v1/academic_years', headers: headers(@owner), params: { include_classes: 'true' }
    assert_response :success
    assert_equal %w[1A 1AB], response.parsed_body.dig('data', 'academic_years').find { |row| row['id'] == @year.id }['classes']
    @student.student_enrollments.update_all(status: StudentEnrollment.statuses[:transferred])
    get '/api/school/v1/academic_years', headers: headers(@manager), params: { include_classes: 'true' }
    assert_equal [], response.parsed_body.dig('data', 'academic_years').first['classes']
  end

  test 'dropdown exact class matching does not include prefixes or legacy banbie and preserves old search' do
    @other_class.update!(banbie: '1A')
    get '/api/school/v1/students', headers: headers(@owner), params: { school_academic_year_id: @year.id, class_name_exact: '1A' }
    assert_response :success
    assert_equal [@student.id], response.parsed_body.dig('data', 'students').map { |row| row['id'] }
    assert_equal 1, response.parsed_body.dig('data', 'pagination', 'total_count')
    get '/api/school/v1/students', headers: headers(@owner), params: { school_academic_year_id: @year.id, class_name: '1A' }
    assert_response :success
    assert_equal 2, response.parsed_body.dig('data', 'students').length
    get '/api/school/v1/students', headers: headers(@manager), params: { school_academic_year_id: @year.id, class_name_exact: '1AB' }
    assert_response :success
    assert_empty response.parsed_body.dig('data', 'students')
  end

  test 'class catalogue uses a bounded query count across many years' do
    5.times { |n| student(year(@school), "Class-#{n}") }
    queries = []
    subscriber = lambda do |*args|
      payload = args.last
      sql = payload[:sql]
      queries << sql if sql.start_with?('SELECT') && sql.match?(/student_enrollments|school_academic_years/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get '/api/school/v1/password_managers/classes', headers: headers(@owner)
    end
    assert_response :success
    assert_equal 6, response.parsed_body.dig('data', 'academic_years').length
    assert_operator queries.length, :<=, 2
  end

  test 'existing teacher keeps credentials and teaching access when portal access is granted disabled and removed' do
    teacher = employed_teacher(@year)
    teaching_headers = headers(teacher)
    original = teacher.attributes.slice('email', 'encrypted_password', 'nickname', 'school_id')
    before = GeneralUser.count
    post '/api/school/v1/password_managers', headers: headers(@owner), as: :json,
      params: { teacher_id: teacher.id, grants: [grant(@year, '1A')] }
    assert_response :created
    assert_equal true, response.parsed_body.dig('data', 'account', 'linked_teacher')
    assert_equal before, GeneralUser.count
    assert_equal original, teacher.reload.attributes.slice(*original.keys)
    assert_equal 'teacher', teacher.aienglish_role
    assert_equal ['essay'], teacher.aienglish_features_list
    assert_equal @school.id, teacher.school_password_access['school_id']
    get '/api/v1/essay_assignments', headers: teaching_headers
    assert_response :success

    post '/general_users/sign_in.json', as: :json, params: { general_user: { email: teacher.email, password: 'Password123!' } }
    assert_response :success
    post '/api/school_admin/v1/session', as: :json, params: { email: teacher.email, password: 'Password123!' }
    assert_response :success
    assert_equal 'school_password_manager', response.parsed_body.dig('data', 'user', 'aienglish_role')
    assert_equal @school.id, response.parsed_body.dig('data', 'school', 'id')
    portal_headers = { 'Authorization' => response.headers['Authorization'] }
    assert portal_headers['Authorization'].present?
    payload = Warden::JWTAuth::TokenDecoder.new.call(portal_headers['Authorization'].delete_prefix('Bearer '))
    assert_equal teacher.school_password_access['session_version'], payload['school_password_version']
    get '/api/school/v1/students', headers: portal_headers, params: { school_academic_year_id: @year.id }
    assert_response :success
    assert_equal [@student.id], response.parsed_body.dig('data', 'students').map { |u| u['id'] }
    post "/api/school/v1/students/#{@student.id}/reset_password", headers: portal_headers, as: :json,
      params: { school_academic_year_id: @year.id }
    assert_response :success
    post "/api/school/v1/students/#{@other_class.id}/reset_password", headers: portal_headers, as: :json,
      params: { school_academic_year_id: @year.id }
    assert_response :not_found
    get '/api/v1/essay_assignments', headers: portal_headers
    assert_response :forbidden
    get '/api/school/v1/password_managers/teachers', headers: portal_headers
    assert_response :forbidden
    get '/api/school/v1/me', headers: teaching_headers
    assert_response :forbidden

    # Switch browser identities: the owner's bearer request has no teacher login cookie.
    reset!
    host! 'localhost'
    patch "/api/school/v1/password_managers/#{teacher.id}", headers: headers(@owner), as: :json,
      params: { revision: teacher.school_password_access['revision'], password: 'Another123!' }
    assert_response :unprocessable_entity
    assert_equal original, teacher.reload.attributes.slice(*original.keys)
    patch "/api/school/v1/password_managers/#{teacher.id}", headers: headers(@owner), as: :json,
      params: { revision: teacher.school_password_access['revision'], enabled: false }
    assert_response :success
    get '/api/school/v1/me', headers: portal_headers
    assert_includes [401, 403], response.status
    get '/api/v1/essay_assignments', headers: teaching_headers
    assert_response :success
    assert teacher.reload.active_for_authentication?

    delete "/api/school/v1/password_managers/#{teacher.id}", headers: headers(@owner), as: :json,
      params: { revision: teacher.reload.school_password_access['revision'] }
    assert_response :no_content
    assert_equal original, teacher.reload.attributes.slice(*original.keys)
    assert_equal 1, teacher.teacher_assignments.count
    get '/api/school_admin/v1/me', headers: portal_headers
    assert_includes [401, 403], response.status
    reset!
    host! 'localhost'
    post '/api/school/v1/session', as: :json, params: { email: teacher.email, password: 'Password123!' }
    assert_response :unauthorized
    reset!
    host! 'localhost'
    post '/general_users/sign_in.json', as: :json, params: { general_user: { email: teacher.email, password: 'Password123!' } }
    assert_response :success
    normal_headers = { 'Authorization' => response.headers['Authorization'] }
    normal_payload = Warden::JWTAuth::TokenDecoder.new.call(normal_headers['Authorization'].delete_prefix('Bearer '))
    assert_nil normal_payload['school_password_version']
    get '/api/v1/essay_assignments', headers: normal_headers
    assert_response :success
    get '/api/v1/essay_assignments', headers: teaching_headers
    assert_response :success
  end

  test 'teacher selection rejects foreign inactive historical and non teacher identities' do
    teacher = employed_teacher(@year)
    foreign_school = School.create!(name: 'Foreign', code: SecureRandom.hex(6), meta: {})
    foreign = employed_teacher(year(foreign_school))
    inactive = employed_teacher(@year)
    inactive.teacher_assignments.update_all(status: TeacherAssignment.statuses[:resigned])
    historical_year = year(@school)
    historical = employed_teacher(historical_year)
    historical_year.update!(status: :archived)
    get '/api/school/v1/password_managers/teachers', headers: headers(@owner)
    assert_response :success
    assert_equal [teacher.id], response.parsed_body.dig('data', 'teachers').map { |u| u['id'] }
    [foreign, inactive, historical, @student, @owner].each do |target|
      post '/api/school/v1/password_managers', headers: headers(@owner), as: :json,
        params: { teacher_id: target.id, grants: [grant(@year, '1A')] }
      assert_response :not_found
      assert_empty target.reload.school_password_access
    end
    post '/api/school/v1/password_managers', headers: headers(@manager), as: :json,
      params: { teacher_id: teacher.id, grants: [] }
    assert_response :forbidden
    post '/api/school/v1/password_managers', headers: headers(@owner), as: :json,
      params: { teacher_id: teacher.id, email: 'overwrite@example.test', grants: [] }
    assert_response :unprocessable_entity
    assert_empty teacher.reload.school_password_access
  end

  test 'duplicate teacher grants conflict and explicit reauthorization never restores an old portal token' do
    teacher = employed_teacher(@year)
    authorize = -> { post '/api/school/v1/password_managers', headers: headers(@owner), as: :json, params: { teacher_id: teacher.id, grants: [grant(@year, '1A')] } }
    authorize.call
    assert_response :created
    original_access = teacher.reload.school_password_access.deep_dup
    foreign_school = School.create!(name: 'Second employer', code: SecureRandom.hex(6), meta: {})
    foreign_owner = user('school_admin', foreign_school)
    TeacherAssignment.create!(general_user: teacher, school_academic_year: year(foreign_school), status: :active,
      department: 'English', position: 'Teacher', meta: {})
    post '/api/school/v1/password_managers', headers: headers(foreign_owner), as: :json,
      params: { teacher_id: teacher.id, grants: [] }
    assert_response :conflict
    assert_equal original_access, teacher.reload.school_password_access
    authorize.call
    assert_response :conflict
    assert_equal original_access, teacher.reload.school_password_access
    get '/api/school/v1/password_managers/teachers', headers: headers(@owner)
    assert_empty response.parsed_body.dig('data', 'teachers')
    get '/api/school/v1/password_managers', headers: headers(@owner)
    assert_includes response.parsed_body.dig('data', 'accounts').map { |u| u['id'] }, teacher.id
    teacher.school_portal_login = true
    old_headers = headers(teacher)
    delete "/api/school/v1/password_managers/#{teacher.id}", headers: headers(@owner), as: :json,
      params: { revision: original_access['revision'] }
    assert_response :no_content
    authorize.call
    assert_response :created
    refute_equal original_access['session_version'], teacher.reload.school_password_access['session_version']
    get '/api/school/v1/me', headers: old_headers
    assert_response :forbidden
    teacher.school_portal_login = true
    new_headers = headers(teacher)
    get '/api/school/v1/me', headers: new_headers
    assert_response :success
    teacher.teacher_assignments.update_all(status: TeacherAssignment.statuses[:transferred])
    get '/api/school/v1/me', headers: new_headers
    assert_response :forbidden
    assert teacher.reload.active_for_authentication?
  end

  test 'grouped grants never form a cross product of classes across school years' do
    second_year = year(@school)
    second_allowed = student(second_year, '1AB')
    second_denied = student(second_year, '1A')
    @manager.update!(meta: @manager.meta.deep_merge('school_password_access' => {
      'grants' => [grant(@year, '1A'), grant(second_year, '1AB')]
    }))
    [[@year, @student], [second_year, second_allowed]].each do |school_year, allowed|
      get '/api/school/v1/students', headers: headers(@manager), params: { school_academic_year_id: school_year.id }
      assert_response :success
      assert_equal [allowed.id], response.parsed_body.dig('data', 'students').map { |row| row['id'] }
    end
    get '/api/school/v1/academic_years', headers: headers(@manager), params: { include_classes: true }
    assert_response :success
    classes = response.parsed_body.dig('data', 'academic_years').index_by { |row| row['id'] }
    assert_equal ['1A'], classes[@year.id]['classes']
    assert_equal ['1AB'], classes[second_year.id]['classes']
    post "/api/school/v1/students/#{second_denied.id}/reset_password", headers: headers(@manager), as: :json,
      params: { school_academic_year_id: second_year.id }
    assert_response :not_found
  end

  private

  def employed_teacher(school_year)
    user('teacher').tap do |teacher|
      teacher.update!(meta: teacher.meta.merge('aienglish_features_list' => ['essay']))
      TeacherAssignment.create!(general_user: teacher, school_academic_year: school_year, status: :active,
        department: 'English', position: 'Teacher', meta: {})
    end
  end

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
