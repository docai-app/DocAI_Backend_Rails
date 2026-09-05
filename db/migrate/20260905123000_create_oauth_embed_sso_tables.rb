# frozen_string_literal: true

class CreateOauthEmbedSsoTables < ActiveRecord::Migration[7.0]
  def change
    add_column :oauth_applications, :allowed_launch_origins, :jsonb, null: false, default: []
    add_column :oauth_applications, :sso_launch_enabled, :boolean, null: false, default: false

    create_table :oauth_embed_launches, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :client_id, null: false
      t.string :subject, null: false
      t.uuid :assignment_id, null: false
      t.string :mode, null: false
      t.string :return_origin, null: false
      t.string :nonce, null: false
      t.string :request_id, null: false
      t.string :ticket_secret_digest, null: false
      t.integer :key_version, null: false, default: 1
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.uuid :embed_session_id
      t.jsonb :meta, null: false, default: {}
      t.timestamps null: false
    end

    add_index :oauth_embed_launches, %i[client_id nonce], unique: true
    add_index :oauth_embed_launches, :ticket_secret_digest, unique: true
    add_index :oauth_embed_launches, :expires_at,
              where: 'consumed_at IS NULL AND revoked_at IS NULL',
              name: 'oauth_embed_launches_expiry_idx'
    add_index :oauth_embed_launches, %i[subject created_at],
              order: { created_at: :desc },
              name: 'oauth_embed_launches_subject_idx'

    create_table :oauth_embed_sessions, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :session_secret_digest, null: false
      t.string :client_id, null: false
      t.string :subject, null: false
      t.uuid :user_id, null: false
      t.uuid :assignment_id, null: false
      t.uuid :launch_id, null: false
      t.string :parent_origin, null: false
      t.string :mode, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_seen_at
      t.jsonb :meta, null: false, default: {}
      t.timestamps null: false
    end

    add_index :oauth_embed_sessions, :session_secret_digest, unique: true
    add_index :oauth_embed_sessions, %i[id expires_at],
              where: 'revoked_at IS NULL',
              name: 'oauth_embed_sessions_active_idx'
    add_index :oauth_embed_sessions, %i[subject created_at],
              order: { created_at: :desc },
              name: 'oauth_embed_sessions_subject_idx'
    add_foreign_key :oauth_embed_sessions, :general_users, column: :user_id
    add_foreign_key :oauth_embed_sessions, :essay_assignments, column: :assignment_id
    add_foreign_key :oauth_embed_launches, :essay_assignments, column: :assignment_id
  end
end
