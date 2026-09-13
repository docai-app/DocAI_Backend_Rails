require 'test_helper'
require Rails.root.join('lib/admin_sidekiq_authentication').to_s

class AdminSidekiqAuthenticationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'guard authenticates only explicit Sidekiq credentials and does not modify downstream protection' do
    previous = ENV.values_at('SIDEKIQ_ADMIN_USER', 'SIDEKIQ_ADMIN_PASSWORD')
    begin
      ENV['SIDEKIQ_ADMIN_USER'], ENV['SIDEKIQ_ADMIN_PASSWORD'] = 'operator', 'isolated-sidekiq-password'
      hits = 0
      guard = AdminSidekiqAuthentication.new(->(_env) { hits += 1; [403, { 'X-CSRF-Guard' => 'intact' }, ['CSRF rejection']] })
      basic = ActionController::HttpAuthentication::Basic.encode_credentials('operator', 'isolated-sidekiq-password')
      status, headers, = guard.call(Rack::MockRequest.env_for('/sidekiq', 'HTTP_AUTHORIZATION' => basic))
      assert_equal 403, status
      assert_equal 'intact', headers['X-CSRF-Guard']
      assert_equal 1, hits
      [nil, '', 'Bearer server-token', ActionController::HttpAuthentication::Basic.encode_credentials('operator', 'wrong')].each do |header|
        status, = guard.call(Rack::MockRequest.env_for('/sidekiq', { 'HTTP_AUTHORIZATION' => header }.compact))
        assert_includes [400, 401], status # Rack rejects an unsupported auth scheme as 400.
      end
      ENV.delete('SIDEKIQ_ADMIN_PASSWORD')
      assert_equal 401, guard.call(Rack::MockRequest.env_for('/sidekiq', 'HTTP_AUTHORIZATION' => basic)).first
      assert_equal 1, hits
    ensure
      ENV['SIDEKIQ_ADMIN_USER'], ENV['SIDEKIQ_ADMIN_PASSWORD'] = previous
    end
  end
end
