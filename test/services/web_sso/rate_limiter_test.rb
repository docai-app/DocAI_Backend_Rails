# frozen_string_literal: true

require 'test_helper'

class WebSsoRateLimiterTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class FakeRedis
    def initialize
      @counts = Hash.new(0)
    end

    def eval(_script, keys:, argv:)
      raise 'window must be positive' unless argv.first.to_i.positive?

      @counts[keys.first] += 1
    end
  end

  test 'allows the configured number of ticket requests and then rejects' do
    limiter = WebSso::RateLimiter.new(redis: FakeRedis.new)

    WebSso::RateLimiter::LIMITS.fetch('issue').times do
      assert limiter.check!(scope: :issue, identifier: 'student-123')
    end

    assert_raises(WebSso::RateLimiter::RateLimitedError) do
      limiter.check!(scope: :issue, identifier: 'student-123')
    end
  end

  test 'keeps rate limits isolated by identifier' do
    limiter = WebSso::RateLimiter.new(redis: FakeRedis.new)
    WebSso::RateLimiter::LIMITS.fetch('issue').times do
      limiter.check!(scope: :issue, identifier: 'student-123')
    end

    assert limiter.check!(scope: :issue, identifier: 'student-456')
  end
end
