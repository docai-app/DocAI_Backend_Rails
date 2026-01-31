# frozen_string_literal: true

module Api
  module V1
    class AssignmentStatisticsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
    #   before_action :ensure_teacher_and_same_school

      # GET /api/v1/essay_assignments/:essay_assignment_id/statistics
      def show
        statistics_service = AssignmentStatisticsService.new(@essay_assignment)
        statistics = statistics_service.calculate(
          class_name: params[:class_name],
          status: params[:status],
          name: params[:name],
          email: params[:email]
        )

        # 學生列表（分頁）
        students_query = statistics_service.students_query(
          class_name: params[:class_name],
          status: params[:status],
          name: params[:name],
          email: params[:email]
        )

        students = Kaminari.paginate_array(students_query.to_a)
                          .page(params[:page] || 1)
                          .per(params[:per_page] || 25)

        students_data = students.map do |student_assignment|
          student = student_assignment.general_user
          # 從關聯中獲取當前學年的 enrollment
          enrollment = student.current_enrollment
          
          {
            student_id: student.id,
            student_name: student.nickname,
            student_email: student.email,
            class_name: enrollment&.class_name,
            class_number: student.class_no,
            status: student_assignment.status,
            submitted_at: student_assignment.completed_at&.iso8601,
            deadline: student_assignment.deadline&.iso8601,
            is_overdue: student_assignment.overdue?
          }
        end

        render json: {
          success: true,
          statistics: statistics.merge(
            students: students_data
          ),
          meta: {
            pagination: {
              current_page: students.current_page,
              next_page: students.next_page,
              prev_page: students.prev_page,
              total_pages: students.total_pages,
              total_count: students.total_count
            }
          }
        }, status: :ok
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can view statistics' }, 
                 status: :forbidden
          return
        end

        school = current_general_user.get_school
        unless school && @essay_assignment.general_user.get_school&.id == school.id
          render json: { success: false, error: 'You can only view statistics for assignments in your own school' }, 
                 status: :forbidden
        end
      end
    end
  end
end
