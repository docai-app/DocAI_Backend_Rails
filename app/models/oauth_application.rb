# frozen_string_literal: true

# Custom Doorkeeper application (OAuth client).
# Table: oauth_applications
class OauthApplication < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::Application

  self.table_name = 'oauth_applications'

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :redirect_uri, presence: true

  def as_admin_json(include_secret: false)
    {
      id: id,
      name: name,
      client_id: uid,
      confidential: confidential,
      enabled: enabled,
      trusted: trusted,
      redirect_uris: redirect_uri.to_s.split(/\s+/).reject(&:blank?),
      scopes: scopes.to_s,
      logo_url: logo_url,
      homepage_url: homepage_url,
      privacy_policy_url: privacy_policy_url,
      tos_url: tos_url,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
