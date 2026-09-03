# frozen_string_literal: true

module Api
  module V1
    module Public
      # Returns the public settings needed to render a school's student sign-in page.
      class SchoolLoginConfigsController < ApiController
        UNAVAILABLE_MESSAGE = 'This school sign-in page is not available.'

        def show
          school = ::School.active.find_by(
            student_login_enabled: true,
            student_login_slug: normalized_slug
          )

          return render_unavailable unless school&.student_email_domain.present?

          render json: success_payload(school)
        end

        private

        def success_payload(school)
          {
            success: true,
            data: {
              name: school.name,
              student_login_slug: school.student_login_slug,
              student_email_domain: school.student_email_domain,
              student_login_enabled: true,
              logo_url: school.logo_url
            }
          }
        end

        def normalized_slug
          params[:slug].to_s.strip.downcase
        end

        def render_unavailable
          render json: {
            success: false,
            message: UNAVAILABLE_MESSAGE
          }, status: :not_found
        end
      end
    end
  end
end
