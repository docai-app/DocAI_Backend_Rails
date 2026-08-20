# frozen_string_literal: true

require 'test_helper'

class StudentAcademicYearFilterTest < Minitest::Test
  AcademicYear = Struct.new(:id, :name, :status, :start_date, :end_date, :school, keyword_init: true) do
    def active?
      status == 'active'
    end
  end
  Enrollment = Struct.new(:school_academic_year)

  class EnrollmentCollection < Array
    def includes(*)
      self
    end
  end

  class CapturingScope
    attr_reader :where_arguments

    def where(*arguments)
      @where_arguments = arguments
      self
    end
  end

  def test_defaults_to_active_academic_year
    archived_year = academic_year(id: 'past', status: 'archived', start_date: Date.new(2025, 9, 1))
    active_year = academic_year(id: 'current', status: 'active', start_date: Date.new(2026, 9, 1))
    user = user_with_years(archived_year, active_year)

    result = StudentAcademicYearFilter.resolve(user:)

    assert_equal active_year, result.academic_year
    assert_equal [active_year, archived_year], result.available_academic_years
  end

  def test_rejects_academic_year_without_student_enrollment
    user = user_with_years(academic_year(id: 'allowed'))

    assert_raises(StudentAcademicYearFilter::AcademicYearUnavailableError) do
      StudentAcademicYearFilter.resolve(user:, academic_year_id: 'not-allowed')
    end
  end

  def test_allows_all_academic_years_for_an_enrolled_student
    user = user_with_years(academic_year(id: 'past'), academic_year(id: 'current'))

    result = StudentAcademicYearFilter.resolve(
      user:,
      academic_year_id: StudentAcademicYearFilter::ALL_ACADEMIC_YEARS_ID
    )

    assert_nil result.academic_year
    assert_nil result.created_at_range
    assert_equal 2, result.available_academic_years.size
  end

  def test_allows_legacy_students_without_enrollment_when_no_year_is_requested
    result = StudentAcademicYearFilter.resolve(user: user_with_years)

    assert_nil result.academic_year
    assert_empty result.available_academic_years
  end

  def test_allows_all_academic_years_for_legacy_students_without_enrollment
    result = StudentAcademicYearFilter.resolve(
      user: user_with_years,
      academic_year_id: StudentAcademicYearFilter::ALL_ACADEMIC_YEARS_ID
    )

    assert_nil result.academic_year
    assert_nil result.created_at_range
    assert_empty result.available_academic_years
  end

  def test_grading_filter_uses_snapshot_and_created_at_fallback
    year = academic_year(id: 'year-1')
    result = StudentAcademicYearFilter.resolve(user: user_with_years(year))
    scope = CapturingScope.new

    StudentAcademicYearFilter.filter_gradings(scope:, result:)

    sql, values = scope.where_arguments
    assert_includes sql, 'submission_academic_year_id = :academic_year_id'
    assert_includes sql, 'submission_academic_year_id IS NULL'
    assert_equal 'year-1', values[:academic_year_id]
  end

  def test_assignment_filter_separates_submitted_and_unsubmitted_work
    year = academic_year(id: 'year-1')
    result = StudentAcademicYearFilter.resolve(user: user_with_years(year))
    scope = CapturingScope.new
    user = Struct.new(:id).new('student-1')

    StudentAcademicYearFilter.filter_assignments(scope:, result:, user:)

    sql, values = scope.where_arguments
    assert_includes sql, 'EXISTS'
    assert_includes sql, 'NOT EXISTS'
    assert_includes sql, 'assignment_student_assignments.created_at BETWEEN'
    assert_equal 'student-1', values[:general_user_id]
    assert_equal 'year-1', values[:academic_year_id]
  end

  private

  def academic_year(id:, status: 'archived', start_date: Date.new(2025, 9, 1))
    AcademicYear.new(
      id:,
      name: id,
      status:,
      start_date:,
      end_date: start_date.next_year - 1.day,
      school: Struct.new(:timezone).new('Asia/Hong_Kong')
    )
  end

  def user_with_years(*years)
    enrollments = EnrollmentCollection.new(years.map { |year| Enrollment.new(year) })
    Struct.new(:student_enrollments).new(enrollments)
  end
end
