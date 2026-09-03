# frozen_string_literal: true

class OauthPartnerAccountLink < ApplicationRecord
  self.table_name = 'oauth_partner_account_links'

  STATUSES = %w[active revoked].freeze

  belongs_to :oauth_application, class_name: 'OauthApplication'
  belongs_to :general_user

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :linked_at, presence: true
  validates :external_user_id, length: { maximum: 255 }, allow_nil: true
  validates :external_site, length: { maximum: 500 }, allow_nil: true

  scope :active, -> { where(status: 'active') }
  scope :revoked, -> { where(status: 'revoked') }
  scope :active_last_days, lambda { |days|
    active.where('last_active_at >= ? OR linked_at >= ?', days.days.ago, days.days.ago)
  }

  def active?
    status == 'active'
  end

  def revoke!(reason: nil)
    return self unless active?

    update!(
      status: 'revoked',
      revoked_at: Time.current,
      meta: meta.to_h.merge('revoke_reason' => reason).compact
    )
  end

  def touch_active!
    update!(last_active_at: Time.current) if active?
  end

  def as_admin_json
    {
      id: id,
      general_user_id: general_user_id,
      email_masked: mask_email(general_user&.email),
      nickname: general_user&.nickname,
      external_user_id: external_user_id,
      external_site: external_site.presence || oauth_application&.homepage_url,
      status: status,
      linked_at: linked_at,
      last_active_at: last_active_at,
      revoked_at: revoked_at
    }
  end

  # Upsert active binding for user+client. Partner may fill external_user_id later.
  def self.upsert_active!(application:, general_user:, external_user_id: nil, external_site: nil, meta: {})
    link = find_or_initialize_by(
      oauth_application_id: application.id,
      general_user_id: general_user.id,
      status: 'active'
    )

    now = Time.current
    link.linked_at ||= now
    link.last_active_at = now
    link.external_user_id = external_user_id if external_user_id.present?
    link.external_site = external_site if external_site.present?
    link.meta = link.meta.to_h.merge(meta.to_h)
    link.save!
    link
  rescue ActiveRecord::RecordNotUnique
    # Race: another request created active link; update that row.
    existing = active.find_by!(oauth_application_id: application.id, general_user_id: general_user.id)
    existing.update!(
      last_active_at: Time.current,
      external_user_id: external_user_id.presence || existing.external_user_id,
      external_site: external_site.presence || existing.external_site,
      meta: existing.meta.to_h.merge(meta.to_h)
    )
    existing
  end

  def self.revoke_for!(application_id:, general_user_id:, reason: nil)
    active.where(oauth_application_id: application_id, general_user_id: general_user_id).find_each do |link|
      link.revoke!(reason: reason)
    end
  end

  def self.revoke_all_for_application!(application_id:, reason: nil)
    active.where(oauth_application_id: application_id).find_each do |link|
      link.revoke!(reason: reason)
    end
  end

  private

  def mask_email(email)
    return nil if email.blank?

    local, domain = email.to_s.split('@', 2)
    return email if domain.blank?

    masked_local = local.length <= 1 ? '*' : "#{local[0]}***"
    "#{masked_local}@#{domain}"
  end
end
