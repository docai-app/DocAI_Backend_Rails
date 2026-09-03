# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    module Public
      class SchoolLoginConfigsControllerTest < ActionDispatch::IntegrationTest
        self.fixture_table_names = []

        setup do
          host! 'docai-dev.m2mda.com'
        end

        test 'returns enabled school login configuration' do
          school = create_school

          get "/api/v1/public/schools/#{school.student_login_slug}/login_config"

          assert_response :success
          body = JSON.parse(response.body)
          assert_equal true, body['success']
          assert_equal school.name, body.dig('data', 'name')
          assert_equal 'demo-school', body.dig('data', 'student_login_slug')
          assert_equal 'students.demo.edu', body.dig('data', 'student_email_domain')
          assert_equal true, body.dig('data', 'student_login_enabled')
          assert_nil body.dig('data', 'logo_url')
          assert_not body['data'].key?('id')
          assert_not body['data'].key?('contact_email')
        end

        test 'normalizes slug when looking up configuration' do
          create_school

          get '/api/v1/public/schools/DEMO-SCHOOL/login_config'

          assert_response :success
        end

        test 'returns the same not found response for disabled and unknown schools' do
          create_school(student_login_enabled: false)

          get '/api/v1/public/schools/demo-school/login_config'
          assert_unavailable_response

          get '/api/v1/public/schools/unknown-school/login_config'
          assert_unavailable_response
        end

        test 'does not return inactive school configuration' do
          create_school(status: :inactive)

          get '/api/v1/public/schools/demo-school/login_config'

          assert_unavailable_response
        end

        test 'does not return incomplete school configuration' do
          school = create_school
          school.update_column(:student_email_domain, nil)

          get '/api/v1/public/schools/demo-school/login_config'

          assert_unavailable_response
        end

        private

        def create_school(attributes = {})
          ::School.create!({
            name: "Login School #{SecureRandom.hex(4)}",
            code: "LOGIN_#{SecureRandom.hex(4).upcase}",
            status: :active,
            meta: {},
            student_login_enabled: true,
            student_login_slug: 'demo-school',
            student_email_domain: 'students.demo.edu'
          }.merge(attributes))
        end

        def assert_unavailable_response
          assert_response :not_found
          body = JSON.parse(response.body)
          assert_equal false, body['success']
          assert_equal 'This school sign-in page is not available.', body['message']
        end
      end
    end
  end
end
