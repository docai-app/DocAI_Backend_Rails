# frozen_string_literal: true

module Api
  module V1
    class ScheduledTasksController < ApiController
      def create
        workflow_id = params[:workflow_id]
        cron = params[:cron]
        entity_name = params[:entity_name]
        user = current_general_user

        task_name = Digest::SHA1.hexdigest("#{workflow_id}#{cron}#{user.id}")

        ScheduledTask.create!(name: task_name, description: "Scheduled task for #{workflow_id}", user:, dag_id:, cron:,
                              status: 0)

        Sidekiq.set_schedule(task_name,
                             { 'class' => 'DagScheduleJob', 'args' => [workflow_id, user.id, entity_name, task_name],
                               'cron' => cron })
      end
    end
  end
end
