# frozen_string_literal: true

require 'test_helper'

module Api
  module Admin
    module V1
      class SchoolsControllerTest < ActionDispatch::IntegrationTest
        self.fixture_table_names = []

        setup do
          host! 'docai-dev.m2mda.com'
        end

        test 'creates and returns student login settings' do
          post '/api/admin/v1/schools', params: {
            school: school_payload
          }

          assert_response :created
          body = JSON.parse(response.body)
          assert_equal 'success', body['status']
          assert_equal true, body.dig('data', 'student_login_enabled')
          assert_equal 'demo-admin-school', body.dig('data', 'student_login_slug')
          assert_equal 'students.admin.edu', body.dig('data', 'student_email_domain')
          assert_equal 'https://aienglish.docai.net/login/demo-admin-school',
                       body.dig('data', 'student_login_url')
        end

        test 'updates student login settings including disabling login' do
          school = ::School.create!(
            name: 'Admin Update School',
            code: 'ADMIN_UPDATE_SCHOOL',
            status: :active,
            meta: { 'region' => 'hk' },
            student_login_enabled: true,
            student_login_slug: 'admin-update-school',
            student_email_domain: 'students.update.edu'
          )

          patch "/api/admin/v1/schools/#{school.code}", params: {
            school: {
              name: school.name,
              student_login_enabled: false
            }
          }

          assert_response :success
          body = JSON.parse(response.body)
          assert_equal false, body.dig('data', 'student_login_enabled')
          assert_equal false, school.reload.student_login_enabled
        end

        private

        def school_payload
          {
            name: 'Admin Login School',
            code: 'ADMIN_LOGIN_SCHOOL',
            status: 'active',
            region: 'hk',
            school_type: 'primary',
            curriculum_type: 'local',
            academic_system: '6_3_3',
            student_login_enabled: true,
            student_login_slug: 'Demo-Admin-School',
            student_email_domain: '@Students.Admin.EDU',
            academic_years: [{
              name: '2026-2027',
              status: 'active',
              start_year: 2026,
              start_month: 9,
              end_month: 8
            }]
          }
        end
      end
    end
  end
end
