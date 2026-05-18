# frozen_string_literal: true

module Api
  module School
    module V1
      class AcademicYearsController < SchoolApiController
        def index
          years = current_school.school_academic_years.order(start_date: :desc)

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
          }
        end
      end
    end
  end
end
