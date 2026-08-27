# frozen_string_literal: true

# OAuth tables live in public schema only (Apartment excluded_models).
class CreateDoorkeeperTables < ActiveRecord::Migration[7.0]
  def up
    return unless on_public_schema?
    return if table_exists?(:oauth_applications)

    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.boolean :confidential, null: false, default: true
      t.boolean :enabled, null: false, default: false
      t.boolean :trusted, null: false, default: false
      t.string :logo_url
      t.string :homepage_url
      t.string :privacy_policy_url
      t.string :tos_url
      t.timestamps null: false
    end

    add_index :oauth_applications, :uid, unique: true
    add_index :oauth_applications, :enabled

    create_table :oauth_access_grants do |t|
      t.uuid :resource_owner_id, null: false
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :code_challenge
      t.string :code_challenge_method
    end

    add_index :oauth_access_grants, :token, unique: true
    add_index :oauth_access_grants, :resource_owner_id

    create_table :oauth_access_tokens do |t|
      t.uuid :resource_owner_id
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, null: false, default: ''
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_index :oauth_access_tokens, :resource_owner_id

    add_foreign_key :oauth_access_grants, :general_users, column: :resource_owner_id
    add_foreign_key :oauth_access_tokens, :general_users, column: :resource_owner_id

    create_table :oauth_audit_logs, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :event, null: false
      t.bigint :oauth_application_id
      t.uuid :general_user_id
      t.string :ip
      t.string :user_agent
      t.jsonb :meta, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :oauth_audit_logs, :event
    add_index :oauth_audit_logs, :oauth_application_id
    add_index :oauth_audit_logs, :general_user_id
    add_index :oauth_audit_logs, :created_at
    add_foreign_key :oauth_audit_logs, :oauth_applications, column: :oauth_application_id
    add_foreign_key :oauth_audit_logs, :general_users, column: :general_user_id
  end

  def down
    return unless on_public_schema?

    drop_table :oauth_audit_logs, if_exists: true
    drop_table :oauth_access_tokens, if_exists: true
    drop_table :oauth_access_grants, if_exists: true
    drop_table :oauth_applications, if_exists: true
  end

  private

  # Apartment sets Tenant.current to "public" on the public schema (not blank).
  def on_public_schema?
    return true unless defined?(Apartment)

    current = Apartment::Tenant.current
    current.blank? || current == 'public'
  end
end
