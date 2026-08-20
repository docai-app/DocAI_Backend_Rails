# frozen_string_literal: true

# Resolves a student-visible academic year and applies the same year boundary
# rules to assigned work and grading history.
class StudentAcademicYearFilter
  ALL_ACADEMIC_YEARS_ID = 'all'
  Result = Struct.new(:academic_year, :created_at_range, :available_academic_years, keyword_init: true)

  class AcademicYearUnavailableError < StandardError; end

  def self.resolve(user:, academic_year_id: nil)
    new(user:, academic_year_id:).resolve
  end

  def self.filter_gradings(scope:, result:)
    return scope unless result&.academic_year

    scope.where(
      <<~SQL.squish,
        essay_gradings.submission_academic_year_id = :academic_year_id
        OR (
          essay_gradings.submission_academic_year_id IS NULL
          AND essay_gradings.created_at BETWEEN :start_at AND :end_at
        )
      SQL
      academic_year_id: result.academic_year.id,
      start_at: result.created_at_range.begin,
      end_at: result.created_at_range.end
    )
  end

  def self.filter_assignments(scope:, result:, user:)
    return scope unless result&.academic_year

    submitted_status = EssayGrading.statuses.fetch('draft')
    range = result.created_at_range

    scope.where(
      <<~SQL.squish,
        EXISTS (
          SELECT 1
          FROM essay_gradings submitted_gradings
          WHERE submitted_gradings.essay_assignment_id = assignment_student_assignments.essay_assignment_id
            AND submitted_gradings.general_user_id = :general_user_id
            AND submitted_gradings.status <> :draft_status
            AND (
              submitted_gradings.submission_academic_year_id = :academic_year_id
              OR (
                submitted_gradings.submission_academic_year_id IS NULL
                AND submitted_gradings.created_at BETWEEN :start_at AND :end_at
              )
            )
        )
        OR (
          NOT EXISTS (
            SELECT 1
            FROM essay_gradings submitted_gradings
            WHERE submitted_gradings.essay_assignment_id = assignment_student_assignments.essay_assignment_id
              AND submitted_gradings.general_user_id = :general_user_id
              AND submitted_gradings.status <> :draft_status
          )
          AND assignment_student_assignments.created_at BETWEEN :start_at AND :end_at
        )
      SQL
      general_user_id: user.id,
      draft_status: submitted_status,
      academic_year_id: result.academic_year.id,
      start_at: range.begin,
      end_at: range.end
    )
  end

  def initialize(user:, academic_year_id: nil)
    @user = user
    @academic_year_id = academic_year_id.to_s.presence
  end

  def resolve
    years = available_academic_years

    if @academic_year_id == ALL_ACADEMIC_YEARS_ID
      return Result.new(academic_year: nil, created_at_range: nil, available_academic_years: years)
    end

    if years.empty?
      raise AcademicYearUnavailableError, 'The selected academic year is not available.' if @academic_year_id

      return Result.new(academic_year: nil, created_at_range: nil, available_academic_years: [])
    end

    academic_year = requested_academic_year(years) || default_academic_year(years)

    Result.new(
      academic_year:,
      created_at_range: created_at_range_for(academic_year),
      available_academic_years: years
    )
  end

  private

  def available_academic_years
    @user.student_enrollments
         .includes(school_academic_year: :school)
         .filter_map(&:school_academic_year)
         .uniq(&:id)
         .sort_by(&:start_date)
         .reverse
  end

  def requested_academic_year(years)
    return if @academic_year_id.blank?

    years.find { |year| year.id.to_s == @academic_year_id } ||
      raise(AcademicYearUnavailableError, 'The selected academic year is not available.')
  end

  def default_academic_year(years)
    years.select(&:active?).max_by(&:start_date) || years.max_by(&:start_date)
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
