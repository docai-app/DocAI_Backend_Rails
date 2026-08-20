# frozen_string_literal: true

# Resolves a teacher-visible academic year into the school's local-time range,
# or returns no range when the caller explicitly requests all years.
class EssayAssignmentAcademicYearFilter
  ALL_ACADEMIC_YEARS_ID = 'all'
  Result = Struct.new(:academic_year, :created_at_range, keyword_init: true)

  class AcademicYearUnavailableError < StandardError; end
  class ActiveAcademicYearMissingError < StandardError; end

  def self.resolve!(user:, academic_year_id: nil)
    new(user:, academic_year_id:).resolve!
  end

  def initialize(user:, academic_year_id: nil)
    @user = user
    @academic_year_id = academic_year_id.to_s.presence
  end

  def resolve!
    return Result.new(academic_year: nil, created_at_range: nil) if all_academic_years_requested?

    academic_year = requested_academic_year || active_academic_year

    Result.new(
      academic_year:,
      created_at_range: created_at_range_for(academic_year)
    )
  end

  private

  def all_academic_years_requested?
    @academic_year_id == ALL_ACADEMIC_YEARS_ID
  end

  def available_academic_years
    @available_academic_years ||= @user.teacher_assignments
                                       .includes(school_academic_year: :school)
                                       .filter_map(&:school_academic_year)
                                       .uniq(&:id)
  end

  def requested_academic_year
    return if @academic_year_id.blank?

    available_academic_years.find { |year| year.id.to_s == @academic_year_id } ||
      raise(
        AcademicYearUnavailableError,
        'The selected academic year is not available for this account.'
      )
  end

  def active_academic_year
    available_academic_years
      .select(&:active?)
      .max_by(&:start_date) ||
      raise(
        ActiveAcademicYearMissingError,
        'No current academic year is available for this account.'
      )
  end

  def created_at_range_for(academic_year)
    zone = school_time_zone(academic_year.school)
    start_date = academic_year.start_date
    end_date = academic_year.end_date
    start_at = zone.local(start_date.year, start_date.month, start_date.day).beginning_of_day
    end_at = zone.local(end_date.year, end_date.month, end_date.day).end_of_day

    start_at..end_at
  end

  def school_time_zone(school)
    zone_name = school&.timezone.presence
    school_zone = ActiveSupport::TimeZone[zone_name] if zone_name

    school_zone || Time.zone || ActiveSupport::TimeZone['UTC']
  end
end
