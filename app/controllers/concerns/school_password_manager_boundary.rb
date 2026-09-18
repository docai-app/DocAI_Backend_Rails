# frozen_string_literal: true

# Protect generic API entry points as well as the two school portal aliases.
module SchoolPasswordManagerBoundary
  extend ActiveSupport::Concern

  ALLOWED_ACTIONS = {
    'api/school/v1/sessions' => %w[create destroy],
    'api/school/v1/profiles' => %w[show],
    'api/school/v1/academic_years' => %w[index],
    'api/school/v1/students' => %w[index show reset_password]
  }.freeze

  included do
    before_action :restrict_school_password_manager!
  end

  private

  def restrict_school_password_manager!
    # Login authenticates the credentials being submitted, not a previous cookie.
    return if controller_path == 'api/school/v1/sessions' && action_name == 'create'

    actor = current_general_user
    return unless actor&.school_password_manager?

    response.headers['Cache-Control'] = 'no-store'
    token = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    version = Warden::JWTAuth::TokenDecoder.new.call(token)['school_password_version'] if token.present?
    valid_session = version.present? && version == actor.school_password_access['session_version']
    return if actor.active_for_authentication? && valid_session &&
              ALLOWED_ACTIONS.fetch(controller_path, []).include?(action_name)

    render json: { success: false, error: 'Forbidden.' }, status: :forbidden
  rescue JWT::DecodeError
    render json: { success: false, error: 'Invalid session.' }, status: :unauthorized
  end
end
