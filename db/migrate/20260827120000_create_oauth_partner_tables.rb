# frozen_string_literal: true

# Partner account links + outbound webhook config/deliveries (public schema only).
class CreateOauthPartnerTables < ActiveRecord::Migration[7.0]
  def up
    return unless on_public_schema?

    create_partner_account_links unless table_exists?(:oauth_partner_account_links)
    create_application_webhooks unless table_exists?(:oauth_application_webhooks)
    create_webhook_deliveries unless table_exists?(:oauth_webhook_deliveries)
  end

  def down
    return unless on_public_schema?

    drop_table :oauth_webhook_deliveries, if_exists: true
    drop_table :oauth_application_webhooks, if_exists: true
    drop_table :oauth_partner_account_links, if_exists: true
  end

  private

  def create_partner_account_links
    create_table :oauth_partner_account_links, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :oauth_application, null: false, foreign_key: { to_table: :oauth_applications }
      t.uuid :general_user_id, null: false
      t.string :external_user_id
      t.string :external_site
      t.string :status, null: false, default: 'active'
      t.datetime :linked_at, null: false
      t.datetime :last_active_at
      t.datetime :revoked_at
      t.jsonb :meta, null: false, default: {}
      t.timestamps null: false
    end

    add_index :oauth_partner_account_links, :general_user_id
    add_index :oauth_partner_account_links, :status
    add_index :oauth_partner_account_links, :linked_at
    add_index :oauth_partner_account_links, :last_active_at
    add_index :oauth_partner_account_links,
              %i[oauth_application_id general_user_id],
              unique: true,
              where: "status = 'active'",
              name: 'index_oauth_links_active_app_user'
    add_index :oauth_partner_account_links,
              %i[oauth_application_id external_user_id],
              unique: true,
              where: "status = 'active' AND external_user_id IS NOT NULL",
              name: 'index_oauth_links_active_app_external_user'

    add_foreign_key :oauth_partner_account_links, :general_users, column: :general_user_id
  end

  def create_application_webhooks
    create_table :oauth_application_webhooks do |t|
      t.references :oauth_application, null: false, foreign_key: { to_table: :oauth_applications }, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :url
      t.string :signing_secret
      t.jsonb :subscribed_events, null: false, default: []
      t.integer :timeout_seconds, null: false, default: 10
      t.integer :max_retries, null: false, default: 5
      t.jsonb :custom_headers, null: false, default: {}
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.timestamps null: false
    end
  end

  def create_webhook_deliveries
    create_table :oauth_webhook_deliveries, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :oauth_application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempt_count, null: false, default: 0
      t.integer :last_http_status
      t.text :last_error
      t.datetime :next_retry_at
      t.datetime :delivered_at
      t.timestamps null: false
    end

    add_index :oauth_webhook_deliveries, %i[oauth_application_id created_at],
              name: 'index_oauth_webhook_deliveries_on_app_and_created'
    add_index :oauth_webhook_deliveries, %i[status next_retry_at],
              name: 'index_oauth_webhook_deliveries_on_status_retry'
    add_index :oauth_webhook_deliveries, :event_type
  end

  def on_public_schema?
    return true unless defined?(Apartment)

    current = Apartment::Tenant.current
    current.blank? || current == 'public'
  end
end
