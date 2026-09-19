require 'time'

# Read-only. A live worker OR a surviving in-memory timer is not sufficient.
class ReliabilityScheduleHealth
  DEFINITIONS = {
    'reports' => ['ai_english_operations_report', 'operations_reports', 'OperationsReportTickJob'],
    'recovery' => ['ai_english_generation_recovery', 'generation_recovery', 'EssayGenerationRecoveryJob']
  }.freeze

  def self.call(now: Time.now)
    require 'sidekiq/api'
    workers = Sidekiq::ProcessSet.new.to_a
    rows = DEFINITIONS.map do |role, (name, queue, job)|
      schedule = Sidekiq.get_schedule(name)
      heartbeat = Sidekiq.redis { |r| r.hgetall("aienglish:#{queue}:health") }
      last_tick = SidekiqScheduler::RedisManager.get_job_last_time(name)
      evaluate(role: role, schedule: schedule, heartbeat: heartbeat, last_tick: last_tick,
               workers: workers, now: now)
    end
    { healthy: rows.all? { |row| row[:issues].empty? }, roles: rows, checked_at: now.iso8601 }
  rescue StandardError => e
    { healthy: false, roles: [], issues: ['health_check_unavailable'], error_class: e.class.name, checked_at: now.iso8601 }
  end

  def self.evaluate(role:, schedule:, heartbeat:, last_tick:, workers:, now:)
    _name, queue, job = DEFINITIONS.fetch(role)
    issues = []
    issues << 'schedule_missing_or_invalid' unless schedule.is_a?(Hash) &&
      schedule['class'] == job && schedule['queue'] == queue &&
      schedule['cron'] == '*/5 * * * * Asia/Macau' && schedule['enabled'] != false
    count = workers.count do |worker|
      Array(worker['queues']).include?(queue) && worker['beat'].to_f > now.to_f - 90 &&
        ![true, 'true'].include?(worker['quiet'])
    end
    issues << 'worker_missing_or_quiet' if count.zero?
    issues << 'schedule_tick_stale' unless recent?(last_tick, now)
    issues << 'successful_completion_stale' unless heartbeat['state'] == 'completed' && recent?(heartbeat['completed_at'], now)
    { role: role, worker_count: count, issues: issues }
  end

  def self.recent?(value, now)
    stamp = Time.parse(value.to_s)
    stamp >= now - 900 && stamp <= now + 60
  rescue ArgumentError
    false
  end
end
