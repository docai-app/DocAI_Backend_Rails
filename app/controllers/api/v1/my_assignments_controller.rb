# frozen_string_literal: true

module Api
  module V1
    class MyAssignmentsController < ApiController
      before_action :authenticate_general_user!
      # before_action :ensure_student

      # GET /api/v1/essay_assignments/my_assignments
      def index
        teacher_assignments = current_general_user.my_assignments(status: params[:status])
                                                  .includes(:essay_assignment)
                                                  .order('assignment_student_assignments.created_at DESC')

        feed_items = teacher_assignments.map { |assignment| teacher_assignment_json(assignment) }
        feed_items.concat(active_assignment_packages_json)
        feed_items.sort_by! { |item| item[:sort_time] || Time.zone.at(0) }
        feed_items.reverse!

        assignments = Kaminari.paginate_array(feed_items).page(params[:page] || 1)
                                                        .per(params[:per_page] || 25)
        assignments_data = assignments.map { |item| item.except(:sort_time) }

        # 統計信息
        all_assignments = current_general_user.my_assignments
        active_packages_count = current_general_user.assignment_packages.where(status: %i[generating active failed]).count
        statistics = {
          assigned_count: all_assignments.assigned.count,
          completed_count: all_assignments.completed.count,
          overdue_count: all_assignments.overdue.count,
          assignment_packages_count: active_packages_count
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
            statistics: statistics
          }
        }, status: :ok
      end

      private

      def ensure_student
        unless current_general_user.aienglish_role == 'student'
          render json: { success: false, error: 'Only students can view their assignments' }, 
                 status: :forbidden
        end
      end

      def teacher_assignment_json(assignment)
        essay_assignment = assignment.essay_assignment
        {
          type: 'teacher_assignment',
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
          updated_at: assignment.updated_at.iso8601,
          sort_time: assignment.created_at
        }
      end

      def active_assignment_packages_json
        current_general_user.assignment_packages
                            .where(status: %i[generating active failed])
                            .includes(assignment_package_items: :essay_assignment)
                            .order(created_at: :desc)
                            .map do |assignment_package|
          assignment_package.as_list_json.merge(
            type: 'assignment_package',
            sort_time: assignment_package.created_at
          )
        end
      end
    end
  end
end
