# frozen_string_literal: true

class SchoolAdminAuditLog < ApplicationRecord
  self.table_name = 'school_admin_audit_logs'

  belongs_to :school
  belongs_to :actor, class_name: 'GeneralUser', foreign_key: :actor_id, optional: true

  validates :action, presence: true
  validates :school_id, presence: true
  validates :actor_id, presence: true
end
