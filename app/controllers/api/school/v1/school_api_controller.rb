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
          return if current_general_user&.portal_school_admin?

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

        def students_scope
          GeneralUser.joins(student_enrollments: :school_academic_year)
                     .where(school_academic_years: { school_id: current_school.id })
                     .distinct
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
