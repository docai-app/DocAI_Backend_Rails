# frozen_string_literal: true

class AddSchoolIdToGeneralUsersAndSchoolAdminAuditLogs < ActiveRecord::Migration[7.0]
  def change
    add_reference :general_users, :school, type: :uuid, foreign_key: true, index: true, null: true

    create_table :school_admin_audit_logs, id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid :actor_id, null: false
      t.string :actor_role, null: false, default: 'school_admin'
      t.uuid :school_id, null: false
      t.string :action, null: false
      t.string :target_type
      t.string :target_id
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.text :user_agent
      t.datetime :created_at, null: false
    end

    add_index :school_admin_audit_logs, :school_id
    add_index :school_admin_audit_logs, %i[school_id created_at]
    add_foreign_key :school_admin_audit_logs, :schools
    add_foreign_key :school_admin_audit_logs, :general_users, column: :actor_id
  end
end
