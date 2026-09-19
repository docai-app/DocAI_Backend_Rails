require 'uri'

# Applied after dotenv and before clients/gems load. Opt-in; separate Redis hosts
# are never silently retargeted. Secrets remain server-only environment values.
module RedisCredentials
  def self.apply!(env)
    user = env['AI_ENGLISH_REDIS_USERNAME']
    password = env['AI_ENGLISH_REDIS_PASSWORD']
    return if user.to_s.empty? && password.to_s.empty?
    raise 'Incomplete Redis authentication settings' unless user.to_s.match?(/\A[a-z0-9_]+\z/) && password.to_s.match?(/\A[0-9a-f]{64}\z/)
    urls = %w[REDIS_URL REDIS_CACHE_URL].filter_map do |key|
      next if env[key].to_s.empty?
      uri = URI.parse(env[key])
      raise 'Unexpected Redis authentication target' unless %w[redis rediss].include?(uri.scheme) && uri.host == env.fetch('AI_ENGLISH_REDIS_HOST', 'redis') && uri.port == 6379
      uri.user = user
      uri.password = password
      [key, uri.to_s]
    end
    raise 'Redis URL missing' if urls.empty?
    urls.each { |key, value| env[key] = value }
  rescue URI::InvalidURIError
    raise 'Invalid Redis authentication target'
  end
end
