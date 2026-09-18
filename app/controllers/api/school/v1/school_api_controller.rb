# frozen_string_literal: true

module Api
  module School
    module V1
      class SchoolApiController < ApiController
        include Devise::Controllers::Helpers

        before_action :authenticate_general_user!
        before_action :require_portal_school_admin!

        private

        def require_portal_school_admin!
          response.headers['Cache-Control'] = 'no-store'
          actor = current_general_user
          return if actor&.active_for_authentication? && (actor.portal_school_admin? || actor.portal_password_manager?)

          render json: { success: false, error: 'Forbidden.' }, status: :forbidden
        end

        def current_school
          @current_school ||= current_general_user.school
        end

        def teacher_ids_for_current_school
          @teacher_ids_for_current_school ||= GeneralUser.joins(teacher_assignments: :school_academic_year)
                                                       .where(school_academic_years: { school_id: current_school.id })
                                                       .distinct
                                                       .pluck(:id)
        end

        def assignments_scope
          EssayAssignment.where(general_user_id: teacher_ids_for_current_school)
        end

        def authorized_student_enrollments
          scope = StudentEnrollment.joins(:school_academic_year)
                                   .where(school_academic_years: { school_id: current_school.id, status: SchoolAcademicYear.statuses[:active] })
                                   .where(status: StudentEnrollment.statuses[:active])
          grants = current_general_user.school_password_grants
          grants.reduce(scope.none) do |allowed, grant|
            allowed.or(scope.where(school_academic_year_id: grant['school_academic_year_id'], class_name: grant['class_name']))
          end
        end

        def students_scope
          scope = GeneralUser.joins(student_enrollments: :school_academic_year)
                             .where(school_academic_years: { school_id: current_school.id }).distinct
          return scope unless current_general_user.school_password_manager?

          scope.where(student_enrollments: { id: authorized_student_enrollments.select(:id) })
               .where("general_users.meta->>'aienglish_role' = ?", 'student')
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            next_page: collection.next_page,
            prev_page: collection.prev_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end
      end
    end
  end
end
