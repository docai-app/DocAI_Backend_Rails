# frozen_string_literal: true

module Api
  module School
    module V1
      class SessionsController < ApiController
        include Devise::Controllers::Helpers

        before_action :authenticate_general_user!, only: [:destroy]
        before_action :require_portal_school_admin!, only: [:destroy]

        def create
          email = params[:email].to_s.strip.downcase
          password = params[:password].to_s
          user = GeneralUser.find_for_database_authentication(email: email)
          puts "user: #{email} #{password} #{user.inspect}"

          unless user&.active_for_authentication? && user.valid_password?(password) && user.portal_school_admin?
            return render json: { success: false, error: 'Invalid email or password.' }, status: :unauthorized
          end

          sign_in(:general_user, user)
          SchoolPortal::AuditLogger.log!(
            actor: user,
            school: user.school,
            action: 'school_admin_signed_in',
            request: request
          )

          render json: {
            success: true,
            message: 'Logged in successfully.',
            data: {
              user: session_user_json(user),
              school: session_school_json(user.school)
            }
          }, status: :ok
        end

        def destroy
          user = current_general_user
          school = user.school
          SchoolPortal::AuditLogger.log!(
            actor: user,
            school: school,
            action: 'school_admin_signed_out',
            request: request
          )
          sign_out(:general_user)
          render json: { success: true, message: 'Logged out.' }, status: :ok
        end

        private

        def require_portal_school_admin!
          return if current_general_user&.portal_school_admin?

          render json: { success: false, error: 'Forbidden.' }, status: :forbidden
        end

        def session_user_json(user)
          user.as_json(only: %i[id email nickname created_at updated_at school_id],
                       methods: [])
              .merge('aienglish_role' => user.aienglish_role)
        end

        def session_school_json(school)
          return nil if school.blank?

          school.as_json(only: %i[id name code status]).merge(
            'logo_url' => school.try(:logo_url)
          )
        end
      end
    end
  end
end
