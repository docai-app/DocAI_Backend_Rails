# frozen_string_literal: true

# Account metadata is server-owned. No schema migration is required.
module SchoolPasswordAccess
  extend ActiveSupport::Concern

  # Transient marker for school portal JWT dispatch; never persisted.
  attr_accessor :school_portal_login

  def dedicated_school_password_manager?
    meta['aienglish_role'] == 'school_password_manager'
  end

  def linked_school_password_teacher?
    aienglish_role == 'teacher' && school_password_access['school_id'].present?
  end

  def school_password_manager?
    dedicated_school_password_manager? || linked_school_password_teacher?
  end

  def school_portal_school
    linked_school_password_teacher? ? School.find_by(id: school_password_access['school_id']) : school
  end

  def school_portal_role
    school_password_manager? ? 'school_password_manager' : aienglish_role
  end

  def school_password_access
    value = meta['school_password_access']
    value.is_a?(Hash) ? value : {}
  end

  def school_password_grants
    value = school_password_access['grants']
    return [] unless value.is_a?(Array)

    value.select do |grant|
      grant.is_a?(Hash) && grant['school_academic_year_id'].is_a?(String) &&
        grant['class_name'].is_a?(String) && grant['class_name'].present?
    end
  end

  def portal_password_manager?
    return false unless school_password_manager? && school_password_access['enabled'] == true &&
                        school_password_access['deleted_at'].blank?
    return school_id.present? if dedicated_school_password_manager?

    # Re-check employment on portal requests, including after transfer/resignation.
    teacher_assignments.joins(:school_academic_year).where(status: :active,
      school_academic_years: { school_id: school_password_access['school_id'], status: SchoolAcademicYear.statuses[:active] }).exists?
  end

  def active_for_authentication?
    super && (!dedicated_school_password_manager? || portal_password_manager?)
  end

  def school_portal_capabilities
    if portal_school_admin?
      %w[students passwords accounts school_overview]
    elsif portal_password_manager?
      %w[students passwords]
    else
      []
    end
  end
end
