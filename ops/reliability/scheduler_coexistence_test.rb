# Run standalone, outside Rails test discovery: only dedicated local Redis.
# RELIABILITY_TEST_REDIS_URL=redis://127.0.0.1:56391/0 bundle exec ruby ...
require 'uri'
url = ENV.fetch('RELIABILITY_TEST_REDIS_URL')
uri = URI(url)
abort 'Dedicated loopback Redis port required' unless uri.host == '127.0.0.1' && uri.port == 56391 && uri.path == '/0'
ENV['REDIS_URL'] = url
require 'sidekiq'
require 'sidekiq/capsule'
require 'sidekiq-scheduler'
require 'minitest/autorun'
require 'minitest/mock'
require 'yaml'
require 'time'

class OperationsReportTickJob
  def self.perform_async; end
end
class EssayGenerationRecoveryJob
  def self.perform_async; end
end

class ReliabilitySchedulerCoexistenceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  REPORT = 'ai_english_operations_report'
  RECOVERY = 'ai_english_generation_recovery'

  def setup
    @prior = ENV.to_h.select { |k, _| k.start_with?('AI_ENGLISH_REPORT', 'AI_ENGLISH_RECOVERY') }
    @prior.each_key { |k| ENV.delete(k) }
    [REPORT, RECOVERY, 'unrelated_existing_schedule'].each { |name| Sidekiq.remove_schedule(name) }
    Sidekiq.set_schedule('unrelated_existing_schedule', {'class' => 'ExistingJob', 'queue' => 'unrelated', 'cron' => '0 0 * * *'})
    @managers = []
  end

  def teardown
    @managers.each(&:stop)
    ENV.keys.grep(/\AAI_ENGLISH_(REPORT|RECOVERY)/).each { |k| ENV.delete(k) }
    ENV.update(@prior)
    [REPORT, RECOVERY, 'unrelated_existing_schedule'].each { |name| Sidekiq.remove_schedule(name) }
  end

  def boot(role, enabled: true)
    # New process starts without another process's in-memory schedule/scheduler.
    Sidekiq.instance_variable_set(:@schedule, nil)
    SidekiqScheduler::Scheduler.instance_variable_set(:@instance, nil)
    suffix = {reports: '_operations_reports', recovery: '_generation_recovery', main: ''}.fetch(role)
    yaml = YAML.unsafe_load_file(File.join(ROOT, 'config', "sidekiq#{suffix}.yml"))
    config = Sidekiq::Config.new
    config[:scheduler] = yaml.fetch(:scheduler)
    config.queues = yaml.fetch(:queues)
    manager = SidekiqScheduler::Manager.new(SidekiqScheduler::Config.new(sidekiq_config: config))
    @managers << manager
    manager.start
    return Sidekiq::Scheduler.instance if role == :main
    prefix = role == :reports ? 'AI_ENGLISH_REPORT' : 'AI_ENGLISH_RECOVERY'
    enabled_prefix = role == :reports ? 'AI_ENGLISH_REPORTS' : prefix
    ENV["#{prefix}_WORKER"] = 'true'
    ENV["#{enabled_prefix}_ENABLED"] = enabled.to_s
    ENV["#{enabled_prefix}_ENABLED_AT"] = Time.now.iso8601
    callbacks = []
    target = Object.new
    target.define_singleton_method(:on) { |_event, &block| callbacks << block }
    initializer = role == :reports ? 'operations_reports' : 'essay_generation_recovery'
    Sidekiq.stub(:configure_server, ->(&block) { block.call(target) }) do
      load File.join(ROOT, 'config', 'initializers', "#{initializer}.rb")
    end
    callbacks.each(&:call)
    Sidekiq::Scheduler.instance
  end

  def test_each_start_order_keeps_both_registry_entries_and_unrelated_schedule
    [[:reports, :recovery], [:recovery, :reports]].each do |order|
      first = boot(order[0])
      second = boot(order[1])
      assert_equal [REPORT, RECOVERY, 'unrelated_existing_schedule'].sort, Sidekiq.get_all_schedules.keys.sort
      expected = {reports: REPORT, recovery: RECOVERY}
      assert_equal [expected[order[0]]], first.scheduled_jobs.keys
      assert_equal [expected[order[1]]], second.scheduled_jobs.keys
      assert_equal false, boot(:main).enabled
      assert Sidekiq.get_schedule(REPORT)
      assert Sidekiq.get_schedule(RECOVERY)
    end
  end

  def test_disabled_role_only_removes_its_own_registry_entry
    boot(:reports)
    boot(:recovery)
    disabled = boot(:reports, enabled: false)
    assert_equal false, disabled.enabled
    assert_nil Sidekiq.get_schedule(REPORT)
    assert Sidekiq.get_schedule(RECOVERY)
    assert Sidekiq.get_schedule('unrelated_existing_schedule')
  end

  def test_restarting_one_owner_keeps_the_other_owner
    boot(:reports)
    boot(:recovery)
    boot(:reports)
    boot(:recovery)
    assert Sidekiq.get_schedule(REPORT)
    assert Sidekiq.get_schedule(RECOVERY)
    assert Sidekiq.get_schedule('unrelated_existing_schedule')
  end

  def test_default_gem_startup_reproduces_destructive_empty_yaml_behavior
    Sidekiq.instance_variable_set(:@schedule, nil)
    SidekiqScheduler::Scheduler.instance_variable_set(:@instance, nil)
    config = Sidekiq::Config.new
    config.queues = ['default']
    manager = SidekiqScheduler::Manager.new(SidekiqScheduler::Config.new(sidekiq_config: config))
    @managers << manager
    assert_empty Sidekiq.get_all_schedules
  end
end
