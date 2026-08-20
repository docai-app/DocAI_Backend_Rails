# frozen_string_literal: true

require 'test_helper'

class WebSsoTicketStoreTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class FakeRedis
    attr_reader :entries, :last_expiry

    def initialize
      @entries = {}
    end

    def set(key, value, nx:, ex:)
      return false if nx && @entries.key?(key)

      @last_expiry = ex
      @entries[key] = value
      'OK'
    end

    def eval(_script, keys:, argv:)
      raise 'consume should not receive arguments' unless argv.empty?

      @entries.delete(keys.first)
    end
  end

  class UnavailableRedis
    def set(*)
      raise Redis::BaseError, 'test Redis outage'
    end

    def eval(*)
      raise Redis::BaseError, 'test Redis outage'
    end
  end

  test 'issues a 60 second opaque ticket and consumes it exactly once' do
    redis = FakeRedis.new
    store = WebSso::TicketStore.new(redis: redis, clock: -> { Time.zone.parse('2026-08-20 12:00:00') })
    payload = {
      general_user_id: 'student-123',
      essay_grading_id: 'grading-456',
      purpose: 'view_grading_result'
    }

    ticket = store.issue(payload)

    assert_match(/\A[A-Za-z0-9_-]{40,128}\z/, ticket)
    assert_equal WebSso::TicketStore::TTL_SECONDS, redis.last_expiry
    assert redis.entries.keys.none? { |key| key.include?(ticket) }, 'Redis keys must contain only the ticket digest'

    consumed = store.consume(ticket)
    assert_equal 'student-123', consumed['general_user_id']
    assert_equal 'grading-456', consumed['essay_grading_id']
    assert_equal 'view_grading_result', consumed['purpose']
    assert_equal Time.zone.parse('2026-08-20 12:00:00').iso8601, consumed['issued_at']

    assert_raises(WebSso::TicketStore::InvalidTicketError) { store.consume(ticket) }
  end

  test 'rejects malformed tickets before querying Redis' do
    store = WebSso::TicketStore.new(redis: FakeRedis.new)

    assert_raises(WebSso::TicketStore::InvalidTicketError) { store.consume('not valid') }
  end

  test 'fails closed when Redis is unavailable' do
    store = WebSso::TicketStore.new(redis: UnavailableRedis.new)

    assert_raises(WebSso::TicketStore::UnavailableError) do
      store.issue(general_user_id: 'student', essay_grading_id: 'grading', purpose: 'view_grading_result')
    end
  end
end
