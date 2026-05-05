# frozen_string_literal: true

module Api
  module School
    module V1
      class SnapshotsController < SchoolApiController
        LIMIT = 30

        def show
          students_q = students_scope.order(updated_at: :desc).limit(LIMIT)
          teachers_q = teachers_scope.order(updated_at: :desc).limit(LIMIT)
          assignments_q = assignments_scope.includes(:general_user, :essay_gradings).order(created_at: :desc).limit(LIMIT)
          recent_gradings = EssayGrading.joins(:essay_assignment)
                                        .where(essay_assignments: { general_user_id: teacher_ids_for_current_school })
                                        .includes(:general_user, :essay_assignment)
                                        .order(created_at: :desc)
                                        .limit(LIMIT)
          logs = SchoolAdminAuditLog.where(school_id: current_school.id)
                                    .order(created_at: :desc)
                                    .limit(LIMIT)

          render json: {
            success: true,
            data: {
              school: current_school.as_json(only: %i[id name code status]),
              counts: {
                students: students_scope.count,
                teachers: teachers_scope.count,
                assignments: assignments_scope.count,
                recent_submissions: EssayGrading.joins(:essay_assignment)
                                              .where(essay_assignments: { general_user_id: teacher_ids_for_current_school })
                                              .where('essay_gradings.created_at >= ?', 7.days.ago)
                                              .count
              },
              students: students_q.map { |s| student_row(s) },
              teachers: teachers_q.map { |t| teacher_row(t) },
              assignments: assignments_q.map { |a| assignment_summary(a) },
              submissions: recent_gradings.map { |g| submission_summary(g) },
              logs: logs.map { |l| log_row(l) }
            }
          }, status: :ok
        end

        private

        def teachers_scope
          GeneralUser.joins(teacher_assignments: :school_academic_year)
                     .where(school_academic_years: { school_id: current_school.id })
                     .distinct
        end

        def student_row(user)
          {
            id: user.id,
            nickname: user.nickname,
            email: user.email,
            class_name: user.banbie,
            student_number: user.class_no,
            status: user.locked_at.present? ? 'locked' : 'active',
            updated_at: user.updated_at
          }
        end

        def teacher_row(user)
          {
            id: user.id,
            nickname: user.nickname,
            email: user.email,
            updated_at: user.updated_at
          }
        end

        def assignment_summary(assignment)
          {
            id: assignment.id,
            title: assignment.title,
            topic: assignment.topic,
            category: assignment.category,
            created_at: assignment.created_at,
            submissions_count: assignment.essay_gradings.size,
            creator: assignment.general_user ? {
              id: assignment.general_user.id,
              nickname: assignment.general_user.nickname,
              email: assignment.general_user.email
            } : nil
          }
        end

        def submission_summary(grading)
          {
            id: grading.id,
            status: grading.status,
            score: grading.score,
            created_at: grading.created_at,
            assignment_id: grading.essay_assignment_id,
            student: {
              id: grading.general_user_id,
              nickname: grading.general_user&.nickname,
              email: grading.general_user&.email
            }
          }
        end

        def log_row(log)
          {
            id: log.id,
            actor_id: log.actor_id,
            action: log.action,
            target_type: log.target_type,
            target_id: log.target_id,
            metadata: log.metadata,
            ip_address: log.ip_address,
            created_at: log.created_at
          }
        end
      end
    end
  end
end
