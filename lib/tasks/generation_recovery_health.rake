require 'sidekiq/api'

namespace :aienglish do
  desc 'Read recovery worker/schedule/heartbeat health without rerunning submissions'
  task recovery_status: :environment do
    schedule = Sidekiq.get_schedule('ai_english_generation_recovery')
    workers = Sidekiq::ProcessSet.new.select { |process| Array(process['queues']).include?('generation_recovery') }
    heartbeat = Sidekiq.redis { |redis| redis.hgetall('aienglish:generation_recovery:health') }
    completed = Time.iso8601(heartbeat['completed_at']) rescue nil
    puts JSON.pretty_generate(
      schedule_registered: schedule.present?, schedule: schedule&.slice('class', 'queue', 'cron'),
      worker_count: workers.size, heartbeat: heartbeat,
      recent_successful_scan: heartbeat['state'] == 'completed' && completed.present? && completed >= 15.minutes.ago,
      note: 'A recent scan is not proof of successful provider recovery. Verify a dedicated test record separately.'
    )
  end
end
