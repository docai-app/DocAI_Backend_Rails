# frozen_string_literal: true

require 'redis'

module EssayOcr
  # Keeps an authenticated account from accidentally exhausting the OCR quota.
  class RateLimiter
    WINDOW_SECONDS = Integer(ENV.fetch('ESSAY_OCR_RATE_LIMIT_WINDOW_SECONDS', 600))
    USER_LIMIT = Integer(ENV.fetch('ESSAY_OCR_RATE_LIMIT_PER_USER', 30))
    IP_LIMIT = Integer(ENV.fetch('ESSAY_OCR_RATE_LIMIT_PER_IP', 90))
    INCREMENT_SCRIPT = <<~LUA
      local current = redis.call('INCR', KEYS[1])
      if current == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
      end
      return current
    LUA

    def initialize(redis: self.class.redis, request_id: nil)
      @redis = redis
      @request_id = request_id
    end

    def check!(user_id:, ip:)
      check_key!("user:#{user_id}", USER_LIMIT)
      check_key!("ip:#{ip}", IP_LIMIT)
    rescue MoonshotService::Error
      raise
    rescue Redis::BaseError => e
      Rails.logger.error({ tag: 'essay_ocr_rate_limit', error: e.class.name, message: e.message }.to_json)
      raise MoonshotService::Error.new(
        'Essay recognition is temporarily unavailable. Please try again shortly.',
        http_status: 503,
        error_code: 'ESSAY_OCR_RATE_LIMIT_UNAVAILABLE',
        request_id: @request_id
      )
    end

    def self.redis
      @redis ||= Redis.new(url: ENV['REDIS_URL'].presence || 'redis://127.0.0.1:6379/0')
    end

    private

    def check_key!(suffix, limit)
      key = "docai:essay_ocr:rate:#{suffix}"
      count = @redis.eval(INCREMENT_SCRIPT, keys: [key], argv: [WINDOW_SECONDS])
      return if count <= limit

      raise MoonshotService::Error.new(
        'Too many essay recognition requests. Please wait a few minutes and try again.',
        http_status: 429,
        error_code: 'ESSAY_OCR_RATE_LIMITED',
        request_id: @request_id
      )
    end
  end
end
