# frozen_string_literal: true

require 'test_helper'

class EssayOcrRateLimiterTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class FakeRedis
    def initialize
      @counts = Hash.new(0)
    end

    def eval(_script, keys:, argv:)
      raise 'expiry must be configured' unless argv.first.to_i.positive?

      @counts[keys.first] += 1
    end
  end

  class UnavailableRedis
    def eval(*)
      raise Redis::BaseError, 'test Redis outage'
    end
  end

  test 'allows requests below the configured limits' do
    limiter = EssayOcr::RateLimiter.new(redis: FakeRedis.new)

    assert_nothing_raised { limiter.check!(user_id: 42, ip: '203.0.113.5') }
  end

  test 'rejects requests above the per-user limit' do
    limiter = EssayOcr::RateLimiter.new(redis: FakeRedis.new, request_id: 'ocr-request-123')
    EssayOcr::RateLimiter::USER_LIMIT.times do
      limiter.check!(user_id: 42, ip: '203.0.113.5')
    end

    error = assert_raises(EssayOcr::MoonshotService::Error) do
      limiter.check!(user_id: 42, ip: '203.0.113.5')
    end
    assert_equal 429, error.http_status
    assert_equal 'ESSAY_OCR_RATE_LIMITED', error.error_code
    assert_equal 'ocr-request-123', error.request_id
  end

  test 'fails closed when Redis is unavailable' do
    limiter = EssayOcr::RateLimiter.new(redis: UnavailableRedis.new, request_id: 'ocr-request-redis')

    error = assert_raises(EssayOcr::MoonshotService::Error) do
      limiter.check!(user_id: 42, ip: '203.0.113.5')
    end
    assert_equal 503, error.http_status
    assert_equal 'ESSAY_OCR_RATE_LIMIT_UNAVAILABLE', error.error_code
  end
end
