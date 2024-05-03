# frozen_string_literal: true

class GeneralUserScheduleReminderJob
  include Sidekiq::Worker

  queue_as :general_user_schedule_reminder_job

  sidekiq_options retry: 3, dead: true, queue: 'general_user_schedule_reminder_job',
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(id)
    @ScheduledTask = ScheduledTask.find(id)
    puts "====== task_name ====== task_name: #{@ScheduledTask.name}"
    puts "====== task_description ====== task_description: #{@ScheduledTask.description}"
    # NewGeneralUserScheduledTaskNotifier.with(target_phone_number: @ScheduledTask.user.phone, message: @ScheduledTask.description).deliver_later(@ScheduledTask.user)
    begin
      NewGeneralUserScheduledTaskNotifier.with(target_phone_number: @ScheduledTask.user.phone,
                                               message: @ScheduledTask.description).deliver_later(@ScheduledTask.user)
    rescue StandardError => e
      puts "====== GG! Error ====== error: #{e.message}"
      raise e # Re-raise the exception to ensure it gets logged or handled properly
    end
    @ScheduledTask.update(status: 2)
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
