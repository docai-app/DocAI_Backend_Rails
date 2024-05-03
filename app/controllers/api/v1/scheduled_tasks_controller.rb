# frozen_string_literal: true

module Api
  module V1
    class ScheduledTasksController < ApiController
      before_action :authenticate_general_user!, only: %i[index show create update destroy]
      before_action :check_user_info, only: [:create]

      def index
        @scheduled_tasks = current_general_user.scheduled_tasks
        render json: { success: true, scheduled_tasks: @scheduled_tasks }, status: :ok
      end

      def show
        @scheduled_task = ScheduledTask.find(params[:id])
        render json: { success: true, scheduled_task: @scheduled_task }, status: :ok
      end

      def create
        # workflow_id = params[:workflow_id]
        # cron = params[:cron]
        # entity_name = params[:entity_name]
        user = current_general_user

        scheduled_task = ScheduledTask.new(schedule_task_params)
        scheduled_task.entity_id = '4f938027-899a-48c4-a95f-6b3c4d30aa07'
        scheduled_task.user = user

        if scheduled_task.save
          render json: { success: true, scheduled_task: }, status: :created
        else
          render json: { success: false, errors: scheduled_task.errors.full_messages }, status: :unprocessable_entity
        end

        # task_name = Digest::SHA1.hexdigest("#{workflow_id}#{cron}#{user.id}")

        # ScheduledTask.create!(name: task_name, description: "Scheduled task for #{workflow_id}", user:, cron:,
        #                       status: 0)

        # Sidekiq.set_schedule(task_name,
        #                      { 'class' => 'GeneralUserScheduleReminderJob', 'args' => [workflow_id, user.id, entity_name, task_name],
        #                        'cron' => cron })
      end

      private

      def schedule_task_params
        params.require(:scheduled_task).permit(:name, :description, :cron, :entity_id, :one_time, :will_run_at)
      end

      def check_user_info
        user = current_general_user
        return if user.phone.present? && user.timezone.present?

        render json: { error: 'You must set your phone number and timezone before scheduling tasks.' },
               status: :unprocessable_entity
      end
    end
  end
end
