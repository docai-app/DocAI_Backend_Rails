# frozen_string_literal: true

module Api
  module V1
    class AssignmentRemindersController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school

      # POST /api/v1/essay_assignments/:essay_assignment_id/send_reminders
      def create
        reminder_service = AssignmentReminderService.new(
          @essay_assignment,
          current_general_user
        )

        result = reminder_service.send_reminders(
          target_students: reminder_params[:target_students]
        )

        if result.success?
          render json: {
            success: true,
            reminders_sent: result.reminders_sent,
            reminders_failed: result.reminders_failed,
            reminders: result.reminders.map { |r| reminder_json(r) },
            failed_students: result.failed_students
          }, status: :ok
        else
          render json: {
            success: false,
            error: result.error_message
          }, status: :unprocessable_entity
        end
      end

      private

      def reminder_params
        # 如果提供了 reminder 参数，提取 target_students；否则返回空数组
        if params[:reminder].present?
          params.require(:reminder).permit(target_students: [])
        else
          ActionController::Parameters.new({}).permit(target_students: [])
        end
      end

      def reminder_json(reminder)
        {
          id: reminder.id,
          student_id: reminder.general_user_id,
          student_name: reminder.general_user.nickname,
          student_email: reminder.general_user.email,
          status: reminder.status,
          sent_at: reminder.sent_at&.iso8601,
          created_at: reminder.created_at.iso8601
        }
      end

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can send reminders' }, 
                 status: :forbidden
          return
        end

        school = current_general_user.get_school
        unless school && @essay_assignment.general_user.get_school&.id == school.id
          render json: { success: false, error: 'You can only send reminders for assignments in your own school' }, 
                 status: :forbidden
        end
      end
    end
  end
end
