# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentAcademicYearFilterTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(
      name: "Academic Year Filter School #{SecureRandom.hex(4)}",
      code: "academic-year-filter-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    @current_year = create_academic_year!(
      name: '2026-2027',
      start_date: Date.new(2026, 8, 1),
      end_date: Date.new(2027, 7, 31),
      status: :active
    )
    @past_year = create_academic_year!(
      name: '2025-2026',
      start_date: Date.new(2025, 8, 1),
      end_date: Date.new(2026, 7, 31),
      status: :archived
    )
    @teacher = create_teacher!
    assign_teacher_to!(@current_year)
    assign_teacher_to!(@past_year)
  end

  test 'defaults to the active academic year' do
    result = EssayAssignmentAcademicYearFilter.resolve!(user: @teacher)

    assert_equal @current_year, result.academic_year
    assert result.created_at_range.cover?(hong_kong_time(2026, 8, 1, 0, 0, 0))
    assert result.created_at_range.cover?(hong_kong_time(2027, 7, 31, 23, 59, 59))
    assert_not result.created_at_range.cover?(hong_kong_time(2026, 7, 31, 23, 59, 59))
  end

  test 'allows an archived academic year assigned to the teacher' do
    result = EssayAssignmentAcademicYearFilter.resolve!(
      user: @teacher,
      academic_year_id: @past_year.id
    )

    assert_equal @past_year, result.academic_year
    assert result.created_at_range.cover?(hong_kong_time(2025, 8, 1, 0, 0, 0))
    assert result.created_at_range.cover?(hong_kong_time(2026, 7, 31, 23, 59, 59))
    assert_not result.created_at_range.cover?(hong_kong_time(2026, 8, 1, 0, 0, 0))
  end

  test 'allows the explicit all academic years option without a date range' do
    result = EssayAssignmentAcademicYearFilter.resolve!(
      user: @teacher,
      academic_year_id: EssayAssignmentAcademicYearFilter::ALL_ACADEMIC_YEARS_ID
    )

    assert_nil result.academic_year
    assert_nil result.created_at_range
  end

  test 'uses the application time zone when the school time zone is blank' do
    @school.update_columns(timezone: nil)

    Time.use_zone('UTC') do
      result = EssayAssignmentAcademicYearFilter.resolve!(user: @teacher)

      assert_equal Time.zone.local(2026, 8, 1).beginning_of_day, result.created_at_range.begin
      assert_equal Time.zone.local(2027, 7, 31).end_of_day, result.created_at_range.end
    end
  end

  test 'rejects an academic year not assigned to the teacher' do
    other_school = School.create!(
      name: "Other Academic Year School #{SecureRandom.hex(4)}",
      code: "other-academic-year-#{SecureRandom.hex(4)}",
      meta: {}
    )
    unavailable_year = SchoolAcademicYear.create!(
      school: other_school,
      name: '2026-2027',
      start_date: Date.new(2026, 8, 1),
      end_date: Date.new(2027, 7, 31),
      status: :active,
      meta: {}
    )

    assert_raises(EssayAssignmentAcademicYearFilter::AcademicYearUnavailableError) do
      EssayAssignmentAcademicYearFilter.resolve!(
        user: @teacher,
        academic_year_id: unavailable_year.id
      )
    end
  end

  test 'raises when the teacher has no active academic year' do
    @current_year.update!(status: :archived)

    assert_raises(EssayAssignmentAcademicYearFilter::ActiveAcademicYearMissingError) do
      EssayAssignmentAcademicYearFilter.resolve!(user: @teacher)
    end
  end

  private

  def create_academic_year!(name:, start_date:, end_date:, status:)
    SchoolAcademicYear.create!(
      school: @school,
      name:,
      start_date:,
      end_date:,
      status:,
      meta: {}
    )
  end

  def create_teacher!
    teacher = GeneralUser.create!(
      email: "academic-year-teacher-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: 'Academic Year Teacher',
      meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => ['essay'] },
      konnecai_tokens: {}
    )
    teacher.create_energy(value: 100) unless teacher.energy
    teacher
  end

  def assign_teacher_to!(academic_year)
    TeacherAssignment.create!(
      general_user: @teacher,
      school_academic_year: academic_year,
      department: 'English',
      position: 'Teacher',
      status: :active,
      meta: {}
    )
  end

  def hong_kong_time(year, month, day, hour, minute, second)
    ActiveSupport::TimeZone['Asia/Hong_Kong'].local(year, month, day, hour, minute, second)
  end
end
