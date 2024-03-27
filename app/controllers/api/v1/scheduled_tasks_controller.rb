# frozen_string_literal: true

module Api
  module V1
    class ScheduledTasksController < ApiControlle
      def create
        dag_id = params[:dag_id]
        cron = params[:cron]
        user = current_general_user

        task_name = Digest::SHA1.hexdigest("#{dag_id}#{cron}#{user.id}")
        ScheduledTask.create!(name: task_name, description: "Scheduled task for #{dag_id}", user:,
                              dag_id:, cron:, status: 0)
      end
    end
  end
end
