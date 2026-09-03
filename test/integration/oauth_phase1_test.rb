# frozen_string_literal: true

require 'test_helper'

class OauthPhase1Test < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @user = GeneralUser.create!(
      email: "oauth-phase1-#{SecureRandom.hex(4)}@example.com",
      password: 'Password123!',
      password_confirmation: 'Password123!',
      nickname: 'OAuth Tester'
    )
  end

  test 'admin can create enable and list oauth clients' do
    post '/api/admin/v1/oauth/clients', params: {
      client: {
        name: 'Partner Demo',
        confidential: true,
        enabled: false,
        scopes: 'openid profile email offline_access',
        redirect_uris: ['https://partner.example.com/oauth/callback']
      }
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 'success', body['status']
    assert body.dig('data', 'client_id').present?
    assert body.dig('data', 'client_secret').present?
    assert_equal false, body.dig('data', 'enabled')

    client_id = body.dig('data', 'id')
    post "/api/admin/v1/oauth/clients/#{client_id}/enable"
    assert_response :success
    assert_equal true, JSON.parse(response.body).dig('data', 'enabled')

    get '/api/admin/v1/oauth/clients'
    assert_response :success
    list = JSON.parse(response.body)['data']
    assert list.any? { |row| row['id'] == client_id }
  end

  test 'authorize rejects disabled client' do
    app = create_oauth_app!(enabled: false)

    get '/oauth/authorize', params: authorize_params(app)
    assert_response :bad_request
    assert_match(/unauthorized_client|not enabled/i, response.body)
  end

  test 'authorize rejects missing pkce even for confidential clients' do
    app = create_oauth_app!(enabled: true)

    get '/oauth/authorize', params: authorize_params(app).except(:code_challenge, :code_challenge_method)
    assert_response :bad_request
    assert_match(/PKCE|code_challenge/i, response.body)
  end

  test 'oauth session can be established for signed-in general user' do
    token = sign_in_token(@user)

    post '/oauth/session',
         headers: { 'Authorization' => token },
         params: { return_to: 'https://docai-dev.m2mda.com/oauth/authorize?client_id=x' }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
  end

  private

  def create_oauth_app!(enabled:)
    app = OauthApplication.new(
      name: 'Test App',
      redirect_uri: 'https://partner.example.com/oauth/callback',
      scopes: 'openid profile email',
      confidential: true,
      enabled: enabled
    )
    app.renew_secret
    app.save!
    app
  end

  def authorize_params(app)
    {
      response_type: 'code',
      client_id: app.uid,
      redirect_uri: 'https://partner.example.com/oauth/callback',
      scope: 'openid profile email',
      state: 'xyz',
      code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      code_challenge_method: 'S256'
    }
  end

  def sign_in_token(user)
    post '/general_users/sign_in',
         params: { general_user: { email: user.email, password: 'Password123!' } },
         as: :json
    response.headers['Authorization']
  end
end
