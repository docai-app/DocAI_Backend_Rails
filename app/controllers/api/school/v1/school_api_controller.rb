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
          @current_school ||= current_general_user.school_portal_school
        end

        def teacher_ids_for_current_school
          @teacher_ids_for_current_school ||= GeneralUser.joins(teacher_assignments: :school_academic_year)
                                                       .where(school_academic_years: { school_id: current_school.id })
                                                       .distinct
                                                       .select(:id)
        end

        def assignments_scope
          scope = EssayAssignment.where(general_user_id: teacher_ids_for_current_school)
          # A shared/transferred teacher is not proof that all of their work belongs here.
          explicit_year = scope.where(school_academic_year_id: current_school.school_academic_years.select(:id))
          other_school_teachers = TeacherAssignment.joins(:school_academic_year)
            .where.not(school_academic_years: { school_id: current_school.id }).select(:general_user_id)
          legacy = scope.where(school_academic_year_id: nil).where.not(general_user_id: other_school_teachers)
          explicit_year.or(legacy)
        end

        def authorized_student_enrollments
          apply_school_password_grants(StudentEnrollment.joins(:school_academic_year))
        end

        # Both catalogue and student reads constrain the same enrollment row.
        # Applying it directly to the existing join avoids a second enrollment subquery.
        def apply_school_password_grants(scope)
          scope = scope.where(school_academic_years: { school_id: current_school.id, status: SchoolAcademicYear.statuses[:active] },
                              student_enrollments: { status: StudentEnrollment.statuses[:active] })
          grants = current_general_user.school_password_grants
          grants.group_by { |grant| grant['school_academic_year_id'] }.reduce(scope.none) do |allowed, (year_id, year_grants)|
            allowed.or(scope.where(student_enrollments: { school_academic_year_id: year_id,
              class_name: year_grants.map { |grant| grant['class_name'] }.uniq }))
          end
        end

        def students_scope
          scope = GeneralUser.joins(student_enrollments: :school_academic_year)
                             .where(school_academic_years: { school_id: current_school.id }).distinct
          return scope unless current_general_user.school_password_manager?

          apply_school_password_grants(scope)
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
