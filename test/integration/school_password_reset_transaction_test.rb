# frozen_string_literal: true

raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'minitest/mock'
require 'timeout'

class SchoolPasswordResetTransactionTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  self.use_transactional_tests = false
  parallelize(workers: 1)

  setup do
    config = GeneralUser.connection_db_config.configuration_hash
    raise 'Unexpected test database' unless Rails.env.test? && config[:host] == '127.0.0.1' &&
      config[:port] == 55439 && config[:database] == 'listening_rails_isolated_test'
    host! 'localhost'
    Apartment::Tenant.switch!('public')
    @users = []
    marker = SecureRandom.hex(8)
    @school = School.create!(name: "Reset transaction #{marker}", code: marker, meta: {})
    @year = SchoolAcademicYear.create!(school: @school, name: marker,
      start_date: Date.current.beginning_of_year, end_date: Date.current.end_of_year, status: :active, meta: {})
    @actors = 2.times.map do
      new_user('school_password_manager', 'school_password_access' => {
        'enabled' => true, 'session_version' => SecureRandom.uuid,
        'grants' => [{ 'school_academic_year_id' => @year.id, 'class_name' => '1A' }]
      })
    end
    @student = new_user('student')
    StudentEnrollment.create!(general_user: @student, school_academic_year: @year,
      class_name: '1A', class_number: '1', status: :active, meta: {})
    @student.update!(locked_at: Time.current, failed_attempts: 20, unlock_token: SecureRandom.hex(16))
    @headers = @actors.map do |actor|
      token, = Warden::JWTAuth::UserEncoder.new.call(actor, :general_user, nil)
      { 'Authorization' => "Bearer #{token}" }
    end
  end

  teardown do
    Apartment::Tenant.switch!('public')
    SchoolAdminAuditLog.where(school_id: @school.id).delete_all
    StudentEnrollment.where(school_academic_year_id: @year.id).delete_all
    GeneralUser.where(id: @users.map(&:id)).delete_all
    @year.delete
    @school.delete
  end

  test 'audit failure rolls back an already saved password and unlock' do
    before = @student.reload.attributes.slice('encrypted_password', 'locked_at', 'failed_attempts', 'unlock_token')
    failed_audit = ->(**_) { SchoolAdminAuditLog.create!(school: @school, actor: @actors.first, action: nil) }
    SchoolPortal::AuditLogger.stub(:log!, failed_audit) do
      post reset_url, headers: @headers.first, params: { school_academic_year_id: @year.id }, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal before, @student.reload.attributes.slice(*before.keys)
    assert @student.valid_password?('Password123!')
    assert_equal 0, SchoolAdminAuditLog.where(school_id: @school.id).count
  end

  test 'two actors resetting the same locked student serialize and both succeed' do
    entered, release, second_pid = Queue.new, Queue.new, Queue.new
    threads = []
    pool = ActiveRecord::Base.connection_pool
    original_log = SchoolPortal::AuditLogger.method(:log!)
    held_log = ->(**args) do
      if args[:actor].id == @actors.first.id
        entered << true
        release.pop
      end
      original_log.call(**args)
    end
    perform_request = ->(index) do
      pool.with_connection do |connection|
        second_pid << connection.select_value('SELECT pg_backend_pid()') if index == 1
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.host! 'localhost'
        session.post reset_url, headers: @headers[index], params: { school_academic_year_id: @year.id }, as: :json
        session.response.status
      end
    end
    SchoolPortal::AuditLogger.stub(:log!, held_log) do
      threads << Thread.new { perform_request.call(0) }
      Timeout.timeout(10) { entered.pop }
      threads << Thread.new { perform_request.call(1) }
      pid = Timeout.timeout(10) { second_pid.pop }.to_i
      # Verify real PostgreSQL blocking, rather than relying on thread timing.
      Timeout.timeout(10) do
        until ActiveRecord::Base.uncached { ActiveRecord::Base.connection.select_value("SELECT cardinality(pg_blocking_pids(#{pid}))").to_i.positive? }
          sleep 0.01
        end
      end
      release << true
      assert_equal [200, 200], Timeout.timeout(10) { threads.map(&:value) }
    end
    assert @student.reload.valid_password?(SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD)
    assert_nil @student.locked_at
    assert_nil @student.unlock_token
    assert_equal 0, @student.failed_attempts
    logs = SchoolAdminAuditLog.where(school_id: @school.id, target_id: @student.id, action: 'student_password_reset')
    assert_equal 2, logs.count
    assert_equal true, logs.find_by!(actor_id: @actors.first.id).metadata['account_unlocked']
    assert_equal false, logs.find_by!(actor_id: @actors.last.id).metadata['account_unlocked']
  ensure
    release << true if release
    threads&.each { |thread| thread.join(5) || thread.kill }
  end

  private

  def new_user(role, extra = {})
    user = GeneralUser.create!(email: "reset-transaction-#{SecureRandom.hex(8)}@example.test",
      password: 'Password123!', school: @school, nickname: role, konnecai_tokens: {},
      meta: { 'aienglish_role' => role, 'aienglish_features_list' => [] }.merge(extra))
    @users << user
    user
  end

  def reset_url
    "/api/school_admin/v1/students/#{@student.id}/reset_password"
  end
end
