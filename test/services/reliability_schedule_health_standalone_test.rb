require 'minitest/autorun'
require_relative '../../app/services/reliability_schedule_health'

class ReliabilityScheduleHealthStandaloneTest < Minitest::Test
  def setup
    @now = Time.utc(2026, 9, 19, 12)
    @args = { role: 'recovery', now: @now,
      schedule: { 'class' => 'EssayGenerationRecoveryJob', 'queue' => 'generation_recovery', 'cron' => '*/5 * * * * Asia/Macau' },
      workers: [{ 'queues' => ['generation_recovery'], 'beat' => @now.to_f, 'quiet' => 'false' }],
      heartbeat: { 'state' => 'completed', 'completed_at' => (@now - 60).iso8601 }, last_tick: (@now - 60).to_s }
  end
  def issues(**changes)
    ReliabilityScheduleHealth.evaluate(**@args.merge(changes))[:issues]
  end
  def test_normal
    assert_empty issues
  end
  def test_missing_registry_not_masked_by_live_worker_and_ticks
    assert_includes issues(schedule: nil), 'schedule_missing_or_invalid'
  end
  def test_wrong_or_disabled_schedule
    assert_includes issues(schedule: @args[:schedule].merge('enabled' => false)), 'schedule_missing_or_invalid'
    assert_includes issues(schedule: @args[:schedule].merge('queue' => 'default')), 'schedule_missing_or_invalid'
  end
  def test_worker_stale_quiet_or_absent
    [[], [{ 'queues' => ['generation_recovery'], 'beat' => 0 }], [@args[:workers][0].merge('quiet' => 'true')]].each do |workers|
      assert_includes issues(workers: workers), 'worker_missing_or_quiet'
    end
  end
  def test_tick_missing_old_or_in_future
    [nil, 'broken', (@now - 901).iso8601, (@now + 70).iso8601].each do |tick|
      assert_includes issues(last_tick: tick), 'schedule_tick_stale'
    end
  end
  def test_running_failed_or_missing_heartbeat_is_not_success
    [{}, @args[:heartbeat].merge('state' => 'running'), @args[:heartbeat].merge('state' => 'failed')].each do |heartbeat|
      assert_includes issues(heartbeat: heartbeat), 'successful_completion_stale'
    end
  end
end
