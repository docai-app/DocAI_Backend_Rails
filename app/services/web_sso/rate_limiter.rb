# frozen_string_literal: true

require 'digest'
require 'redis'

module WebSso
  class RateLimiter
    WINDOW_SECONDS = 60
    # A whole class or school can share one public IP. Keep exchange abuse
    # protection high enough for at least 100 learners opening results together.
    LIMITS = { 'issue' => 10, 'exchange' => 300 }.freeze

    INCREMENT_SCRIPT = <<~LUA.freeze
      local current = redis.call('INCR', KEYS[1])
      if current == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
      end
      return current
    LUA

    class Error < StandardError; end
    class RateLimitedError < Error; end
    class UnavailableError < Error; end

    def initialize(redis: TicketStore.redis)
      @redis = redis
    end

    def check!(scope:, identifier:)
      normalized_scope = scope.to_s
      limit = LIMITS.fetch(normalized_scope)
      normalized_identifier = identifier.to_s.strip
      raise ArgumentError, 'Rate-limit identifier is required.' if normalized_identifier.blank?

      count = @redis.eval(
        INCREMENT_SCRIPT,
        keys: [redis_key(normalized_scope, normalized_identifier)],
        argv: [WINDOW_SECONDS]
      ).to_i
      raise RateLimitedError, 'Too many web sign-in attempts. Please wait and try again.' if count > limit

      true
    rescue KeyError, ArgumentError
      raise
    rescue Redis::BaseError => e
      Rails.logger.error("[WebSso::RateLimiter] Redis unavailable: #{e.class}")
      raise UnavailableError, 'Web sign-in is temporarily unavailable.'
    end

    private

    def redis_key(scope, identifier)
      digest = Digest::SHA256.hexdigest(identifier)
      "web_sso:rate:#{scope}:#{digest}"
    end
  end
end
