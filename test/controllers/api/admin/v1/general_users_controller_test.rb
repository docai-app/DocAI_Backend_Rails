# frozen_string_literal: true

require 'test_helper'

module Api
  module Admin
    module V1
      class GeneralUsersControllerTest < ActionDispatch::IntegrationTest
        self.fixture_table_names = []

        ADMIN_TOKEN = 'test-admin-token'

        setup do
          host! 'docai.m2mda.com'
          @previous_admin_token = ENV.fetch('ADMIN_TOKEN', nil)
          ENV['ADMIN_TOKEN'] = ADMIN_TOKEN

          @bound_at = 2.days.ago.iso8601
          @last_login_at = 1.day.ago.iso8601
          @bound_user = create_general_user(
            'bound',
            'wechat_miniprogram' => {
              'wechat_app_id' => 'wx-test-app',
              'openid' => 'openid-must-not-leak',
              'unionid' => 'unionid-must-not-leak',
              'nickname' => 'WeChat Learner',
              'bound_at' => @bound_at,
              'last_login_at' => @last_login_at
            }
          )
          @unbound_user = create_general_user('unbound')
        end

        teardown do
          if @previous_admin_token.nil?
            ENV.delete('ADMIN_TOKEN')
          else
            ENV['ADMIN_TOKEN'] = @previous_admin_token
          end
        end

        test 'index exposes safe WeChat status and timestamps without identity values' do
          get '/api/admin/v1/general_users', headers: admin_headers, as: :json

          assert_response :success
          users = JSON.parse(response.body).fetch('users')
          bound_json = users.find { |user| user['id'] == @bound_user.id }
          assert_equal true, bound_json.dig('wechat_miniprogram', 'bound')
          assert_equal @bound_at, bound_json.dig('wechat_miniprogram', 'bound_at')
          assert_equal @last_login_at, bound_json.dig('wechat_miniprogram', 'last_login_at')
          assert_equal 'student', bound_json.dig('meta', 'aienglish_role')
          assert_nil bound_json.dig('meta', 'wechat_miniprogram')
          assert_not_includes response.body, 'openid-must-not-leak'
          assert_not_includes response.body, 'unionid-must-not-leak'
        end

        test 'index filters bound and unbound users at the database query' do
          get '/api/admin/v1/general_users',
              params: { wechat_bound: true, keyword: unique_prefix },
              headers: admin_headers,
              as: :json

          assert_response :success
          bound_ids = JSON.parse(response.body).fetch('users').pluck('id')
          assert_equal [@bound_user.id], bound_ids

          get '/api/admin/v1/general_users',
              params: { wechat_bound: false, keyword: unique_prefix },
              headers: admin_headers,
              as: :json

          assert_response :success
          unbound_ids = JSON.parse(response.body).fetch('users').pluck('id')
          assert_equal [@unbound_user.id], unbound_ids
        end

        test 'admin unbind removes only the WeChat binding and is idempotent' do
          path = "/api/admin/v1/general_users/#{@bound_user.id}/wechat_miniprogram/binding"

          delete path, headers: admin_headers, as: :json

          assert_response :success
          first_body = JSON.parse(response.body)
          assert_equal true, first_body['success']
          assert_equal true, first_body['removed']
          assert_equal false, first_body['bound']

          @bound_user.reload
          assert_not @bound_user.wechat_miniprogram_bound?
          assert_equal 'student', @bound_user.meta['aienglish_role']
          assert_equal 'keep-me', @bound_user.meta['profile_preference']

          delete path, headers: admin_headers, as: :json
          assert_response :success
          assert_equal false, JSON.parse(response.body)['removed']
          assert_equal 'keep-me', @bound_user.reload.meta['profile_preference']
        end

        test 'admin unbind requires the admin token' do
          delete "/api/admin/v1/general_users/#{@bound_user.id}/wechat_miniprogram/binding", as: :json

          assert_response :unauthorized
          assert @bound_user.reload.wechat_miniprogram_bound?
        end

        test 'admin unbind returns not found without changing another user' do
          delete '/api/admin/v1/general_users/00000000-0000-4000-8000-000000000000/wechat_miniprogram/binding',
                 headers: admin_headers,
                 as: :json

          assert_response :not_found
          assert @bound_user.reload.wechat_miniprogram_bound?
        end

        private

        def unique_prefix
          @unique_prefix ||= "admin-wechat-#{SecureRandom.hex(5)}"
        end

        def create_general_user(suffix, extra_meta = {})
          GeneralUser.create!(
            email: "#{unique_prefix}-#{suffix}@example.test",
            password: 'Password123!',
            nickname: "Admin WeChat #{suffix}",
            meta: {
              'aienglish_role' => 'student',
              'profile_preference' => 'keep-me'
            }.merge(extra_meta),
            konnecai_tokens: {}
          )
        end

        def admin_headers
          { 'Authorization' => "Bearer #{ADMIN_TOKEN}" }
        end
      end
    end
  end
end
