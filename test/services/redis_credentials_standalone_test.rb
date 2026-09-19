require 'minitest/autorun'
require_relative '../../lib/redis_credentials'

class RedisCredentialsStandaloneTest < Minitest::Test
  def config
    { 'AI_ENGLISH_REDIS_USERNAME' => 'aienglish', 'AI_ENGLISH_REDIS_PASSWORD' => 'a' * 64,
      'REDIS_URL' => 'redis://redis:6379/0', 'REDIS_CACHE_URL' => 'redis://redis:6379/2' }
  end
  def test_opt_in_and_preserve_databases
    blank = { 'REDIS_URL' => 'redis://elsewhere:6380/0' }
    RedisCredentials.apply!(blank)
    assert_equal 'redis://elsewhere:6380/0', blank['REDIS_URL']
    env = config
    RedisCredentials.apply!(env)
    assert_equal "redis://aienglish:#{'a' * 64}@redis:6379/0", env['REDIS_URL']
    assert_equal '/2', URI.parse(env['REDIS_CACHE_URL']).path
  end
  def test_invalid_partial_or_wrong_target_fails_without_partial_change
    ['AI_ENGLISH_REDIS_USERNAME', 'AI_ENGLISH_REDIS_PASSWORD'].each do |key|
      env = config; env.delete(key)
      assert_raises(RuntimeError) { RedisCredentials.apply!(env) }
    end
    env = config.merge('REDIS_CACHE_URL' => 'redis://another-service:6379/2')
    before = env.dup
    assert_raises(RuntimeError) { RedisCredentials.apply!(env) }
    assert_equal before, env
  end
end
