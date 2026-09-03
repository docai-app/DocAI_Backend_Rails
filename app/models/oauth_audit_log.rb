# frozen_string_literal: true

class OauthAuditLog < ApplicationRecord
  self.table_name = 'oauth_audit_logs'

  belongs_to :oauth_application, class_name: 'OauthApplication', optional: true,
                                 foreign_key: :oauth_application_id
  belongs_to :general_user, optional: true

  EVENTS = %w[
    authorize_success
    authorize_denied
    authorize_disabled_client
    token_issued
    token_refresh
    token_rejected
    session_established
    consent_skip_trusted
    revoke_binding
    partner_binding_upserted
  ].freeze

  validates :event, presence: true, inclusion: { in: EVENTS }

  def self.record!(event:, application: nil, general_user: nil, request: nil, meta: {})
    create!(
      event: event.to_s,
      oauth_application_id: application&.id,
      general_user_id: general_user&.id,
      ip: request&.remote_ip,
      user_agent: request&.user_agent.to_s.truncate(500),
      meta: meta.to_h,
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[OauthAuditLog] failed to record #{event}: #{e.message}")
  end
end
