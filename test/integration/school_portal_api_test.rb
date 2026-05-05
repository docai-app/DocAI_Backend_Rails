# frozen_string_literal: true

require 'test_helper'

class SchoolPortalApiTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(
      name: "Portal Test School #{SecureRandom.hex(4)}",
      code: "portal-#{SecureRandom.hex(4)}",
      meta: {}
    )
    @year = SchoolAcademicYear.create!(
      school: @school,
      name: '2025',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active,
      meta: {}
    )
    @admin = GeneralUser.create!(
      email: "school-admin-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: 'School Admin',
      school_id: @school.id,
      meta: { 'aienglish_role' => SchoolPortal::AIENGLISH_ROLE_SCHOOL_ADMIN, 'aienglish_features_list' => [] },
      konnecai_tokens: {}
    )
    @admin.create_energy(value: 100) unless @admin.energy
    @teacher = GeneralUser.create!(
      email: "teacher-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: 'Teacher',
      meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => ['essay'] },
      konnecai_tokens: {}
    )
    @teacher.create_energy(value: 100) unless @teacher.energy
    TeacherAssignment.create!(
      general_user: @teacher,
      school_academic_year: @year,
      department: 'English',
      position: 'Teacher',
      status: :active,
      meta: {}
    )
  end

  test 'portal school admin can log in via school session' do
    post '/api/school/v1/session',
         params: { email: @admin.email, password: 'Password123!' },
         as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert body['data']['user']['id'].present?
  end

  test 'teacher cannot use school session' do
    post '/api/school/v1/session',
         params: { email: @teacher.email, password: 'Password123!' },
         as: :json
    assert_response :unauthorized
  end

  test 'teacher jwt cannot access school snapshot' do
    post '/general_users/sign_in',
         params: { general_user: { email: @teacher.email, password: 'Password123!' } },
         as: :json
    token = response.headers['Authorization'].to_s
    assert token.present?

    get '/api/school/v1/snapshot',
        headers: { 'Authorization' => token },
        as: :json
    assert_response :forbidden
  end

  test 'school_admin alias path behaves like school for login' do
    post '/api/school_admin/v1/session',
         params: { email: @admin.email, password: 'Password123!' },
         as: :json
    assert_response :success
    assert_equal true, JSON.parse(response.body)['success']
  end
end
