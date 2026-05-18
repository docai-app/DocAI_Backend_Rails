# frozen_string_literal: true

module SchoolPortal
  DEFAULT_STUDENT_RESET_PASSWORD = '12345678'

  AIENGLISH_ROLE_SCHOOL_ADMIN = 'school_admin'

  AUDIT_ACTIONS = %w[
    school_admin_signed_in
    school_admin_signed_out
    student_password_reset
    student_viewed
    assignment_list_viewed
    assignment_statistics_viewed
    assignment_viewed
    submission_viewed
    audit_log_client_event
  ].freeze
end
