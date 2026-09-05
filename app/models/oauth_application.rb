# frozen_string_literal: true

# Custom Doorkeeper application (OAuth client).
# Table: oauth_applications
class OauthApplication < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::Application

  self.table_name = 'oauth_applications'

  has_many :partner_account_links, class_name: 'OauthPartnerAccountLink', dependent: :destroy
  has_one :webhook_config, class_name: 'OauthApplicationWebhook', dependent: :destroy
  has_many :webhook_deliveries, class_name: 'OauthWebhookDelivery', dependent: :destroy
  has_many :audit_logs, class_name: 'OauthAuditLog', foreign_key: :oauth_application_id,
                        dependent: :nullify, inverse_of: :oauth_application

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :redirect_uri, presence: true

  def allowed_launch_origins_list
    Array(allowed_launch_origins).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  def sso_launch_allowed?
    enabled? && confidential? && sso_launch_enabled? && allowed_launch_origins_list.any?
  end

  def as_admin_json(include_secret: false, include_stats: false)
    data = {
      id: id,
      name: name,
      client_id: uid,
      confidential: confidential,
      enabled: enabled,
      trusted: trusted,
      sso_launch_enabled: sso_launch_enabled,
      allowed_launch_origins: allowed_launch_origins_list,
      redirect_uris: redirect_uri.to_s.split(/\s+/).reject(&:blank?),
      scopes: scopes.to_s,
      logo_url: logo_url,
      homepage_url: homepage_url,
      privacy_policy_url: privacy_policy_url,
      tos_url: tos_url,
      webhook_enabled: webhook_config&.enabled || false,
      created_at: created_at,
      updated_at: updated_at
    }
    data[:stats] = admin_stats if include_stats
    data
  end

  def admin_stats
    links = partner_account_links
    {
      active_bindings: links.active.count,
      revoked_bindings: links.revoked.count,
      active_last_7d: links.active_last_days(7).count,
      active_last_30d: links.active_last_days(30).count,
      total_authorized_users: OauthAuditLog
        .where(oauth_application_id: id, event: %w[token_issued authorize_success])
        .where.not(general_user_id: nil)
        .distinct
        .count(:general_user_id),
      linked_today: links.where(linked_at: Time.current.beginning_of_day..Time.current.end_of_day).count
    }
  end

  def ensure_webhook_config!
    webhook_config || create_webhook_config!
  end
end
