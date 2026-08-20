# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class ApiV1WechatMiniprogramBindingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  APP_ID = 'wx-test-app-id'
  OPENID = 'wx-test-openid'
  PASSWORD = 'Password123!'

  setup do
    host! 'docai.m2mda.com'
    @user = GeneralUser.create!(
      email: "wechat-unbind-#{SecureRandom.hex(5)}@example.test",
      password: PASSWORD,
      nickname: 'WeChat Unbind Learner',
      meta: {
        'aienglish_role' => 'student',
        'aienglish_features_list' => ['essay'],
        'profile_preference' => 'keep-me',
        'wechat_miniprogram' => {
          'wechat_app_id' => APP_ID,
          'openid' => OPENID,
          'bound_at' => Time.current.iso8601
        }
      },
      konnecai_tokens: {}
    )
  end

  test 'requires a General User JWT' do
    delete binding_path, params: { code: 'fresh-code' }, as: :json

    assert_response :unauthorized
    assert @user.reload.wechat_miniprogram_bound?
  end

  test 'requires a fresh WeChat login code' do
    delete binding_path,
           params: {},
           headers: { 'Authorization' => sign_in_token },
           as: :json

    assert_response :bad_request
    assert_equal 'WECHAT_CODE_REQUIRED', JSON.parse(response.body)['error_code']
    assert @user.reload.wechat_miniprogram_bound?
  end

  test 'unbinds only a matching WeChat identity and keeps the JWT valid' do
    token = sign_in_token

    stub_wechat_session(openid: OPENID) do
      delete binding_path,
             params: { code: 'fresh-code' },
             headers: { 'Authorization' => token },
             as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal false, body['bound']
    assert_nil body['binding']

    @user.reload
    assert_not @user.wechat_miniprogram_bound?
    assert_equal 'keep-me', @user.meta['profile_preference']
    assert_equal 'student', @user.meta['aienglish_role']

    get binding_path, headers: { 'Authorization' => token }, as: :json
    assert_response :success
    assert_equal false, JSON.parse(response.body)['bound']
  end

  test 'rejects a different WeChat identity without changing the binding' do
    stub_wechat_session(openid: 'different-openid') do
      delete binding_path,
             params: { code: 'fresh-code' },
             headers: { 'Authorization' => sign_in_token },
             as: :json
    end

    assert_response :forbidden
    assert_equal 'WECHAT_IDENTITY_MISMATCH', JSON.parse(response.body)['error_code']
    assert_equal OPENID, @user.reload.meta.dig('wechat_miniprogram', 'openid')
    assert_equal 'keep-me', @user.meta['profile_preference']
  end

  test 'is idempotent after the account is already unbound' do
    @user.update!(meta: @user.meta.except('wechat_miniprogram'))

    stub_wechat_session(openid: OPENID) do
      delete binding_path,
             params: { code: 'fresh-code' },
             headers: { 'Authorization' => sign_in_token },
             as: :json
    end

    assert_response :success
    assert_equal false, JSON.parse(response.body)['bound']
    assert_equal 'keep-me', @user.reload.meta['profile_preference']
  end

  private

  def binding_path
    '/api/v1/general_users/wechat_miniprogram/binding'
  end

  def sign_in_token
    post '/general_users/sign_in',
         params: { general_user: { email: @user.email, password: PASSWORD } },
         as: :json
    response.headers['Authorization'].to_s.tap { |token| assert token.present? }
  end

  def stub_wechat_session(openid:, &block)
    WechatMiniprogram::AuthService.stub(:app_id, APP_ID) do
      WechatMiniprogram::AuthService.stub(:jscode2session, { 'openid' => openid }) do
        block.call
      end
    end
  end
end
