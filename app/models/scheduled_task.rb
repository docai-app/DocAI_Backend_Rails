# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_tasks
#
#  name        :string
#  description :string
#  user_type   :string           not null
#  user_id     :uuid             not null
#  dag_id      :uuid
#  cron        :string
#  status      :integer          default("pending")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  entity_id   :uuid
#  one_time    :boolean          default(TRUE)
#  will_run_at :datetime
#  id          :uuid             not null, primary key
#
# Indexes
#
#  index_scheduled_tasks_on_dag_id     (dag_id)
#  index_scheduled_tasks_on_entity_id  (entity_id)
#  index_scheduled_tasks_on_user       (user_type,user_id)
#
class ScheduledTask < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :entity

  enum status: { pending: 0, in_progress: 1, finish: 2 }

  after_create :create_schedule_task
  after_update :update_scheduled_task
  before_destroy :cancel_scheduled_job

  private

  def create_schedule_task
    # 判斷是否為一次性任務
    if one_time
      # 確保 will_run_at 是存在的且格式正確
      puts "====== will_run_at ====== will_run_at: #{will_run_at}"
      raise ArgumentError, 'will_run_at is required for one-time tasks' unless will_run_at.present?

      puts user.inspect
      scheduled_time = Time.use_zone(user.timezone) { Time.zone.parse(will_run_at.to_s) }
      puts "====== scheduled_time ====== scheduled_time: #{scheduled_time}"
    else
      # 確保 cron 是存在的且格式正確
      raise ArgumentError, 'cron is required for recurring tasks' unless cron.present?

      scheduled_time = Time.use_zone(user.timezone) { Time.zone.parse(cron) }
    end
    GeneralUserScheduleReminderJob.perform_at(scheduled_time, id)
  end

  def update_scheduled_task
    return unless saved_change_to_will_run_at? || saved_change_to_cron?

    # Cancel the old scheduled task
    Sidekiq::ScheduledSet.new.find { |job| job.args.first == id }.try(:delete)

    # Confirm the new scheduled time
    scheduled_time = determine_scheduled_time

    # Re-schedule the task
    GeneralUserScheduleReminderJob.perform_at(scheduled_time, id)
  end

  def determine_scheduled_time
    if one_time
      raise ArgumentError, 'will_run_at is required for one-time tasks' unless will_run_at.present?

      Time.use_zone(user.timezone) { Time.zone.parse(will_run_at.to_s) }
    else
      raise ArgumentError, 'cron is required for recurring tasks' unless cron.present?

      Time.use_zone(user.timezone) { Time.zone.parse(cron) }
    end
  end

  def cancel_scheduled_job
    # Find and cancel all Sidekiq jobs related to this task
    Sidekiq::ScheduledSet.new.find { |job| job.args.first == id }.try(:delete)
  end
end
