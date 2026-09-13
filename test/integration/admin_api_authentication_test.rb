# frozen_string_literal: true
require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AdminApiAuthenticationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @previous_token = ENV['ADMIN_TOKEN']
    ENV['ADMIN_TOKEN'] = 'isolated-admin-server-token-with-32-characters'
    @headers = { 'Authorization' => "Bearer #{ENV['ADMIN_TOKEN']}" }
  end

  teardown { ENV['ADMIN_TOKEN'] = @previous_token }

  test 'every routed Admin controller has authentication before other callbacks' do
    controllers = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      controller if controller&.start_with?('api/admin/')
    end.uniq
    assert_operator controllers.size, :>=, 14
    controllers.each do |controller|
      klass = "#{controller.camelize}Controller".constantize
      assert_includes klass.ancestors, AdminAuthenticator, controller
      assert_equal :check_admin_token, klass._process_action_callbacks.select { |cb| cb.kind == :before }.first.filter, controller
    end
  end

  test 'anonymous and invalid credentials cannot read assignments users schools oauth or statistics' do
    paths = %w[essay_assignments essay_assignments/overview essay_assignments/categories essay_gradings/pending_or_stopped
      general_users schools school_academic_years/missing oauth/clients entities users activity_logs
      school_admin_accounts learning_path_templates assignment_packages school-impact-report]
    paths.each do |path|
      [nil, 'Bearer null', 'Bearer undefined', 'Bearer wrong', 'Basic dGVzdDpwdw=='].each do |authorization|
        get "/api/admin/v1/#{path}", headers: { 'Authorization' => authorization }.compact, as: :json
        assert_response :unauthorized, path
        assert_equal 'Unauthorized', response.parsed_body['error']
        assert_equal 'no-store', response.headers['Cache-Control']
        assert_nil response.headers['WWW-Authenticate']
      end
    end
  end

  test 'valid server token retains normal API behavior and missing configuration fails closed' do
    get '/api/admin/v1/essay_assignments/categories', headers: @headers, as: :json
    assert_response :ok
    assert response.parsed_body['success']
    [nil, '', 'null', 'undefined'].each do |value|
      ENV['ADMIN_TOKEN'] = value
      get '/api/admin/v1/essay_assignments/categories', headers: @headers, as: :json
      assert_response :unauthorized
    end
  end

  test 'teacher or student JWT does not grant global Admin access' do
    user = GeneralUser.create!(email: "auth-#{SecureRandom.hex(5)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    get '/api/admin/v1/essay_assignments', headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    assert_response :unauthorized
  end

  test 'rejected write requests cannot enqueue reruns change users or delete records' do
    EssayGenerationJob.clear
    before = [EssayAssignment.count, GeneralUser.count, OauthApplication.count, School.count]
    [['post', 'essay_gradings/missing/rerun_workflow'], ['post', 'essay_gradings/bulk_rerun_workflow'],
     ['patch', 'essay_gradings/bulk_update_status'], ['patch', 'essay_assignments/missing'],
     ['put', 'general_users/missing/password'], ['delete', 'schools/missing'],
     ['post', 'oauth/clients'], ['delete', 'assignment_packages/missing']].each do |method, path|
      public_send(method, "/api/admin/v1/#{path}", params: {}, as: :json)
      assert_response :unauthorized, path
    end
    assert_equal before, [EssayAssignment.count, GeneralUser.count, OauthApplication.count, School.count]
    assert_empty EssayGenerationJob.jobs
  end

  test 'Sidekiq read and control routes reject missing credentials before touching jobs' do
    get '/sidekiq/busy'
    assert_response :unauthorized
    assert_match(/Sidekiq Administration/, response.headers['WWW-Authenticate'])
    post '/sidekiq/quiet', params: {}
    assert_response :unauthorized
  end
end
