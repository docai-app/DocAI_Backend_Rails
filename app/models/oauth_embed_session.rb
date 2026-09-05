# frozen_string_literal: true

class OauthEmbedSession < ApplicationRecord
  self.table_name = 'oauth_embed_sessions'

  MODES = %w[embedded new_tab].freeze

  belongs_to :general_user, foreign_key: :user_id, inverse_of: false
  belongs_to :essay_assignment, foreign_key: :assignment_id, inverse_of: false
  belongs_to :launch, class_name: 'OauthEmbedLaunch', foreign_key: :launch_id, optional: true,
                      inverse_of: false

  validates :session_secret_digest, :client_id, :subject, :user_id, :assignment_id, :launch_id,
            :parent_origin, :mode, :expires_at, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :session_secret_digest, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where('expires_at > ?', Time.current) }

  def active?
    revoked_at.blank? && expires_at > Time.current
  end

  def revoke!(reason: nil)
    return self if revoked_at.present?

    update!(
      revoked_at: Time.current,
      meta: meta.to_h.merge('revoke_reason' => reason).compact
    )
  end

  def touch_seen!
    update_column(:last_seen_at, Time.current) if active?
  end

  def as_bootstrap_json
    {
      version: '1',
      mode: mode,
      launchId: launch_id.to_s,
      assignmentId: assignment_id.to_s,
      parentOrigin: parent_origin,
      sessionExpiresAt: expires_at.utc.iso8601(3)
    }
  end
end
