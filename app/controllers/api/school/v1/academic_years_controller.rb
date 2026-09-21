# frozen_string_literal: true

module Api
  module School
    module V1
      class AcademicYearsController < SchoolApiController
        def index
          years = current_school.school_academic_years.order(start_date: :desc)
          if current_general_user.school_password_manager?
            years = years.where(status: :active, id: current_general_user.school_password_grants.map { |g| g['school_academic_year_id'] })
          end

          if params[:include_classes] == 'true'
            enrollments = if current_general_user.school_password_manager?
                            authorized_student_enrollments
                          else
                            StudentEnrollment.where(school_academic_year_id: years.select(:id))
                          end
            @classes_by_year = enrollments.where.not(class_name: [nil, '']).distinct.order(:class_name)
              .pluck(:school_academic_year_id, :class_name).group_by(&:first)
          end

          render json: {
            success: true,
            data: {
              academic_years: years.map { |ay| academic_year_json(ay) }
            }
          }, status: :ok
        end

        private

        def academic_year_json(ay)
          {
            id: ay.id,
            name: ay.name,
            status: ay.status,
            start_date: ay.start_date,
            end_date: ay.end_date
          }.tap do |row|
            row[:classes] = (@classes_by_year[ay.id] || []).map(&:last) if @classes_by_year
          end
        end
      end
    end
  end
end
