# frozen_string_literal: true

module SchoolPortal
  module AuditLogger
    module_function

    def log!(actor:, school:, action:, target: nil, metadata: nil, request:)
      raise ArgumentError, 'school required' if school.blank?

      SchoolAdminAuditLog.create!(
        actor_id: actor.id,
        actor_role: 'school_admin',
        school_id: school.id,
        action: action.to_s,
        target_type: target&.class&.name,
        target_id: target&.id&.to_s,
        metadata: metadata.presence || {},
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent&.to_s&.truncate(2000),
        created_at: Time.current
      )
    end
  end
end
