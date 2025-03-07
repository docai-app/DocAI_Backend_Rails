# frozen_string_literal: true

class SchoolCreator
  include ActiveModel::Model
  include SchoolConstants

  attr_reader :school
  attr_accessor :name, :code, :status, :address,
                :contact_email, :contact_phone,
                :region, :timezone,
                :school_type, :curriculum_type,
                :academic_system,
                :academic_years, :custom_settings

  validates :name, :code, :region, presence: true
  validate :validate_region
  validate :validate_school_type
  validate :validate_curriculum_type
  validate :validate_academic_system

  def create
    return false unless valid?

    ActiveRecord::Base.transaction do
      create_or_update_school
      create_academic_years
      true
    rescue StandardError => e
      errors.add(:base, e.message)
      false
    end
  end

  private

  def create_or_update_school
    @school = School.find_or_initialize_by(code:)
    @school.assign_attributes(school_attributes)
    @school.save!
  end

  def school_attributes
    {
      name:,
      code:,
      status: status || 'active',
      address:,
      contact_email:,
      contact_phone:,
      timezone: timezone || TIMEZONE_BY_REGION[region],
      meta: {
        region:,
        school_type:,
        curriculum_type:,
        academic_system:,
        custom_settings: custom_settings || {}
      }
    }
  end

  def create_academic_years
    return create_default_academic_year if academic_years.blank?

    academic_years.each do |year_data|
      create_single_academic_year(year_data)
    end
  end

  # ... 其他輔助方法 ...
end
