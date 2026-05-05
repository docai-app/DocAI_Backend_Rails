# frozen_string_literal: true

module Api
  module School
    module V1
      class AssignmentsController < SchoolApiController
        before_action :set_scoped_assignment, only: %i[show submissions]

        def index
          scope = assignments_scope.includes(:general_user, :essay_gradings)

          if params[:search].present?
            search_term = "%#{params[:search]}%"
            scope = scope.joins(:general_user).where(
              'essay_assignments.topic ILIKE ? OR essay_assignments.title ILIKE ? OR essay_assignments.assignment ILIKE ? OR essay_assignments.code ILIKE ? OR general_users.nickname ILIKE ? OR general_users.email ILIKE ?',
              search_term, search_term, search_term, search_term, search_term, search_term
            )
          end

          scope = scope.where(category: params[:category]) if params[:category].present?

          if params[:creator_id].present?
            cid = params[:creator_id].to_s
            scope = if teacher_ids_for_current_school.include?(cid)
                      scope.where(general_user_id: cid)
                    else
                      scope.none
                    end
          end

          if params[:start_date].present?
            scope = scope.where('essay_assignments.created_at >= ?', Date.parse(params[:start_date].to_s))
          end

          if params[:end_date].present?
            scope = scope.where('essay_assignments.created_at <= ?', Date.parse(params[:end_date].to_s).end_of_day)
          end

          sort_by = params[:sort_by].presence || 'created_at'
          sort_order = params[:sort_order].presence || 'desc'

          case sort_by
          when 'submissions_count'
            scope = scope.left_joins(:essay_gradings)
                         .group('essay_assignments.id')
                         .order(Arel.sql("COUNT(essay_gradings.id) #{sort_order == 'asc' ? 'ASC' : 'DESC'}"))
          when 'creator'
            scope = scope.joins(:general_user).order(Arel.sql("general_users.nickname #{sort_order}"))
          else
            table_prefix = %w[created_at updated_at].include?(sort_by) ? 'essay_assignments.' : ''
            scope = scope.order(Arel.sql("#{table_prefix}#{sort_by} #{sort_order}"))
          end

          page = params[:page] || 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          assignments = scope.page(page).per(per_page)

          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: 'assignment_list_viewed',
            request: request
          )

          assignments_data = assignments.map { |a| assignment_row(a) }

          render json: {
            success: true,
            data: {
              assignments: assignments_data,
              pagination: pagination_meta(assignments)
            }
          }, status: :ok
        end

        def show
          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: 'assignment_viewed',
            target: @essay_assignment,
            request: request
          )

          submissions_stats = @essay_assignment.essay_gradings.group(:status).count
          assignment_data = assignment_detail(@essay_assignment, submissions_stats: submissions_stats)

          render json: { success: true, data: { assignment: assignment_data } }, status: :ok
        end

        def submissions
          subs = @essay_assignment.essay_gradings.includes(:general_user)

          subs = subs.where(status: params[:status]) if params[:status].present?

          if params[:student_search].present?
            st = "%#{params[:student_search]}%"
            subs = subs.joins(:general_user).where(
              'general_users.nickname ILIKE ? OR general_users.email ILIKE ?', st, st
            )
          end

          if params[:start_date].present?
            subs = subs.where('essay_gradings.created_at >= ?', Date.parse(params[:start_date].to_s))
          end

          if params[:end_date].present?
            subs = subs.where('essay_gradings.created_at <= ?', Date.parse(params[:end_date].to_s).end_of_day)
          end

          sort_by = params[:sort_by].presence || 'created_at'
          sort_order = params[:sort_order].presence || 'desc'

          case sort_by
          when 'student_name'
            subs = subs.joins(:general_user).order(Arel.sql("general_users.nickname #{sort_order}"))
          when 'score'
            subs = subs.order(Arel.sql("essay_gradings.score #{sort_order}"))
          else
            prefix = %w[created_at updated_at].include?(sort_by) ? 'essay_gradings.' : ''
            subs = subs.order(Arel.sql("#{prefix}#{sort_by} #{sort_order}"))
          end

          page = params[:page] || 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          subs = subs.page(page).per(per_page)

          submissions_data = subs.map do |submission|
            {
              id: submission.id,
              status: submission.status,
              score: submission.score,
              using_time: submission.using_time,
              created_at: submission.created_at,
              updated_at: submission.updated_at,
              student: {
                id: submission.general_user.id,
                nickname: submission.general_user.nickname,
                email: submission.general_user.email,
                class_name: submission.general_user.banbie,
                class_no: submission.general_user.class_no
              },
              submission_class_name: submission.submission_class_name,
              submission_class_number: submission.submission_class_number,
              meta: submission.meta
            }
          end

          render json: {
            success: true,
            data: {
              submissions: submissions_data,
              pagination: pagination_meta(subs)
            }
          }, status: :ok
        end

        private

        def set_scoped_assignment
          @essay_assignment = assignments_scope.includes(:general_user, :essay_gradings).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'Assignment not found' }, status: :not_found
        end

        def assignment_row(assignment)
          {
            id: assignment.id,
            title: assignment.title,
            topic: assignment.topic,
            assignment: assignment.assignment,
            category: assignment.category,
            code: assignment.code,
            answer_visible: assignment.answer_visible,
            remark: assignment.remark,
            created_at: assignment.created_at,
            updated_at: assignment.updated_at,
            submissions_count: assignment.essay_gradings.loaded? ? assignment.essay_gradings.size : assignment.essay_gradings.count,
            creator: assignment.general_user ? {
              id: assignment.general_user.id,
              nickname: assignment.general_user.nickname,
              email: assignment.general_user.email
            } : nil,
            meta: assignment.meta,
            rubric: assignment.rubric
          }
        end

        def assignment_detail(assignment, submissions_stats:)
          recent_submissions = assignment.essay_gradings.includes(:general_user).order('essay_gradings.created_at DESC').limit(10).map do |grading|
            {
              id: grading.id,
              status: grading.status,
              created_at: grading.created_at,
              student: {
                id: grading.general_user.id,
                nickname: grading.general_user.nickname,
                email: grading.general_user.email
              },
              score: grading.score,
              using_time: grading.using_time
            }
          end

          {
            id: assignment.id,
            title: assignment.title,
            topic: assignment.topic,
            assignment: assignment.assignment,
            category: assignment.category,
            code: assignment.code,
            answer_visible: assignment.answer_visible,
            remark: assignment.remark,
            hints: assignment.hints,
            created_at: assignment.created_at,
            updated_at: assignment.updated_at,
            creator: assignment.general_user ? {
              id: assignment.general_user.id,
              nickname: assignment.general_user.nickname,
              email: assignment.general_user.email
            } : nil,
            meta: assignment.meta,
            rubric: assignment.rubric,
            graph_image_url: assignment.graph_image_url,
            statistics: {
              total_submissions: assignment.essay_gradings.count,
              submissions_stats: submissions_stats,
              recent_submissions: recent_submissions
            }
          }
        end
      end
    end
  end
end
