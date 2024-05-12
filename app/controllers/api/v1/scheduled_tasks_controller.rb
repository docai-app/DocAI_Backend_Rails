# frozen_string_literal: true

module Api
  module V1
    class ScheduledTasksController < ApiController
      # before_action :authenticate_general_user!, only: %i[index show create update destroy]
      before_action :find_general_user_by_param, only: %i[index show create update destroy]

      def find_general_user_by_param
        GeneralUser.find_by(id: params[:user_id])
      end

      def index
        status = params[:status] || 'pending'
        user = find_general_user_by_param
        @scheduled_tasks = user.scheduled_tasks.where(status:)
        @scheduled_tasks = Kaminari.paginate_array(@scheduled_tasks).page(params[:page])
        render json: { success: true, scheduled_tasks: @scheduled_tasks, meta: pagination_meta(@scheduled_tasks) },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e }, status: :unprocessable_entity
      end

      def show
        @scheduled_task = ScheduledTask.find(params[:id])
        render json: { success: true, scheduled_task: @scheduled_task }, status: :ok
      rescue StandardError
        render json: { success: false, error: 'Scheduled task not found' }, status: :not_found
      end

      def create
        user = find_general_user_by_param
        check_user_info(user)

        scheduled_task = ScheduledTask.new(schedule_task_params)
        scheduled_task.entity_id = '4f938027-899a-48c4-a95f-6b3c4d30aa07'
        scheduled_task.user = user

        if scheduled_task.save
          render json: { success: true, scheduled_task: }, status: :created
        else
          render json: { success: false, errors: scheduled_task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        @scheduled_task = ScheduledTask.find(params[:id])
        if @scheduled_task.update(schedule_task_params)
          render json: { success: true, scheduled_task: @scheduled_task }, status: :ok
        else
          render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @scheduled_task = ScheduledTask.find(params[:id])
        if @scheduled_task.destroy
          render json: { success: true, message: 'Scheduled task was successfully deleted.' }, status: :ok
        else
          render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def schedule_task_params
        params.require(:scheduled_task).permit(:name, :description, :cron, :entity_id, :one_time, :will_run_at)
      end

      def check_user_info(user)
        return if user.phone.present? && user.timezone.present?

        render json: { error: 'You must set your phone number and timezone before scheduling tasks.' },
               status: :unprocessable_entity
      end

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end
    end
  end
end
