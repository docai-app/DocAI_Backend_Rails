# frozen_string_literal: true

class OauthEmbedLaunch < ApplicationRecord
  self.table_name = 'oauth_embed_launches'

  MODES = %w[embedded new_tab].freeze

  belongs_to :essay_assignment, foreign_key: :assignment_id, inverse_of: false, optional: true
  belongs_to :embed_session, class_name: 'OauthEmbedSession', optional: true

  validates :client_id, :subject, :assignment_id, :mode, :return_origin, :nonce, :request_id,
            :ticket_secret_digest, :expires_at, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :nonce, uniqueness: { scope: :client_id }
  validates :ticket_secret_digest, uniqueness: true

  scope :active, lambda {
    where(consumed_at: nil, revoked_at: nil).where('expires_at > ?', Time.current)
  }

  def active?
    consumed_at.blank? && revoked_at.blank? && expires_at > Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def revoked?
    revoked_at.present?
  end
end
