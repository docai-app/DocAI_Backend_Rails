# frozen_string_literal: true

module Api
  module V1
    class MyAssignmentsController < ApiController
      before_action :authenticate_general_user!
      # before_action :ensure_student

      # GET /api/v1/essay_assignments/my_assignments
      def index
        academic_year_result = StudentAcademicYearFilter.resolve(
          user: current_general_user,
          academic_year_id: params[:school_academic_year_id]
        )

        assignments = current_general_user.my_assignments(status: params[:status])
                                          .includes(:essay_assignment)
                                          .order('assignment_student_assignments.created_at DESC')
        assignments = StudentAcademicYearFilter.filter_assignments(
          scope: assignments,
          result: academic_year_result,
          user: current_general_user
        )

        # 分頁
        assignments = assignments.page(params[:page] || 1).per(params[:per_page] || 25)

        assignments_data = assignments.map do |assignment|
          assignment_json(assignment)
        end

        # 統計信息
        all_assignments = StudentAcademicYearFilter.filter_assignments(
          scope: current_general_user.my_assignments,
          result: academic_year_result,
          user: current_general_user
        )
        statistics = {
          assigned_count: all_assignments.assigned.count,
          completed_count: all_assignments.completed.count,
          overdue_count: all_assignments.overdue.count
        }

        render json: {
          success: true,
          assignments: assignments_data,
          meta: {
            pagination: {
              current_page: assignments.current_page,
              next_page: assignments.next_page,
              prev_page: assignments.prev_page,
              total_pages: assignments.total_pages,
              total_count: assignments.total_count
            },
            statistics: statistics,
            academic_year: academic_year_json(academic_year_result.academic_year)
          }
        }, status: :ok
      rescue StudentAcademicYearFilter::AcademicYearUnavailableError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      private

      def ensure_student
        unless current_general_user.aienglish_role == 'student'
          render json: { success: false, error: 'Only students can view their assignments' }, 
                 status: :forbidden
        end
      end

      def assignment_json(assignment)
        essay_assignment = assignment.essay_assignment
        {
          id: assignment.id,
          essay_assignment: {
            id: essay_assignment.id,
            title: essay_assignment.title,
            topic: essay_assignment.topic,
            category: essay_assignment.category,
            code: essay_assignment.code
          },
          status: assignment.status,
          deadline: assignment.deadline&.iso8601,
          is_overdue: assignment.overdue?,
          days_remaining: assignment.days_remaining,
          has_submission: assignment.has_submission?,
          completed_at: assignment.completed_at&.iso8601,
          created_at: assignment.created_at.iso8601,
          updated_at: assignment.updated_at.iso8601
        }
      end

      def academic_year_json(academic_year)
        return if academic_year.nil?

        {
          id: academic_year.id,
          name: academic_year.name,
          status: academic_year.status
        }
      end
    end
  end
end
