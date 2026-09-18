# frozen_string_literal: true

# Account metadata is server-owned. No schema migration is required.
module SchoolPasswordAccess
  extend ActiveSupport::Concern

  def school_password_manager?
    meta['aienglish_role'] == 'school_password_manager'
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
    school_password_manager? && school_id.present? && school_password_access['enabled'] == true
  end

  def active_for_authentication?
    super && (!school_password_manager? || portal_password_manager?)
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
