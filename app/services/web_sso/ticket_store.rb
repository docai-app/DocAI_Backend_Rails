# frozen_string_literal: true

require 'digest'
require 'json'
require 'redis'
require 'securerandom'

module WebSso
  class TicketStore
    TTL_SECONDS = Integer(ENV.fetch('WEB_SSO_TICKET_TTL_SECONDS', '60'))
    TOKEN_BYTES = 32
    MAX_GENERATION_ATTEMPTS = 3
    KEY_PREFIX = 'web_sso:ticket'

    CONSUME_SCRIPT = <<~LUA.freeze
      local value = redis.call('GET', KEYS[1])
      if value then
        redis.call('DEL', KEYS[1])
      end
      return value
    LUA

    class Error < StandardError; end
    class InvalidTicketError < Error; end
    class UnavailableError < Error; end

    def initialize(redis: self.class.redis, clock: -> { Time.current })
      @redis = redis
      @clock = clock
    end

    def issue(payload)
      normalized_payload = normalize_payload(payload)

      MAX_GENERATION_ATTEMPTS.times do
        ticket = SecureRandom.urlsafe_base64(TOKEN_BYTES, false)
        stored = @redis.set(
          redis_key(ticket),
          JSON.generate(normalized_payload.merge('issued_at' => @clock.call.iso8601)),
          nx: true,
          ex: TTL_SECONDS
        )
        return ticket if stored
      end

      raise UnavailableError, 'Unable to create a unique web sign-in ticket.'
    rescue Redis::BaseError => e
      Rails.logger.error("[WebSso::TicketStore#issue] Redis unavailable: #{e.class}")
      raise UnavailableError, 'Web sign-in is temporarily unavailable.'
    end

    def consume(ticket)
      normalized_ticket = ticket.to_s.strip
      unless valid_ticket_format?(normalized_ticket)
        raise InvalidTicketError, 'The web sign-in ticket is invalid or has expired.'
      end

      raw_payload = @redis.eval(CONSUME_SCRIPT, keys: [redis_key(normalized_ticket)], argv: [])
      raise InvalidTicketError, 'The web sign-in ticket is invalid or has expired.' if raw_payload.blank?

      normalize_payload(JSON.parse(raw_payload))
    rescue JSON::ParserError, TypeError, ArgumentError
      raise InvalidTicketError, 'The web sign-in ticket is invalid or has expired.'
    rescue Redis::BaseError => e
      Rails.logger.error("[WebSso::TicketStore#consume] Redis unavailable: #{e.class}")
      raise UnavailableError, 'Web sign-in is temporarily unavailable.'
    end

    def self.redis
      @redis ||= Redis.new(url: ENV['REDIS_URL'].presence || 'redis://127.0.0.1:6379/0')
    end

    private

    def normalize_payload(payload)
      value = payload.to_h.stringify_keys.slice('general_user_id', 'essay_grading_id', 'purpose', 'issued_at')
      value['general_user_id'] = value['general_user_id'].to_s
      value['essay_grading_id'] = value['essay_grading_id'].to_s
      value['purpose'] = value['purpose'].to_s

      if value['general_user_id'].blank? || value['essay_grading_id'].blank? || value['purpose'] != 'view_grading_result'
        raise ArgumentError, 'Invalid web sign-in ticket payload.'
      end

      value
    end

    def valid_ticket_format?(ticket)
      ticket.length.between?(40, 128) && ticket.match?(/\A[A-Za-z0-9_-]+\z/)
    end

    def redis_key(ticket)
      "#{KEY_PREFIX}:#{Digest::SHA256.hexdigest(ticket)}"
    end
  end
end
