Sidekiq.configure_server do |config|
  config.on(:startup) do
    if ENV['AI_ENGLISH_RECOVERY_WORKER'] == 'true'
      if ENV['AI_ENGLISH_RECOVERY_ENABLED'] == 'true'
        Time.iso8601(ENV.fetch('AI_ENGLISH_RECOVERY_ENABLED_AT'))
        Sidekiq.set_schedule('ai_english_generation_recovery', {
          'cron' => '*/5 * * * * Asia/Macau', 'class' => 'EssayGenerationRecoveryJob', 'queue' => 'generation_recovery'
        })
        Sidekiq.reload_schedule!
        Sidekiq::Scheduler.instance.reload_schedule!
        EssayGenerationRecoveryJob.perform_async
      else
        Sidekiq.remove_schedule('ai_english_generation_recovery')
      end
    end
  end
end
