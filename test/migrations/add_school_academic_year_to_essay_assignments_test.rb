# frozen_string_literal: true

require 'test_helper'
require Rails.root.join('db/migrate/20260827150000_add_school_academic_year_to_essay_assignments')

class AddSchoolAcademicYearToEssayAssignmentsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @school = School.create!(
      name: "Migration Academic Year School #{SecureRandom.hex(4)}",
      code: "migration-academic-year-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Macau',
      meta: {}
    )
    @past_year = create_year!(
      name: '2025-2026',
      start_date: Date.new(2025, 7, 21),
      end_date: Date.new(2026, 8, 14),
      status: :archived
    )
    @current_year = create_year!(
      name: '2026-2027',
      start_date: Date.new(2026, 8, 15),
      end_date: Date.new(2027, 7, 20),
      status: :active
    )
    @teacher = create_teacher!
    assign_teacher_to!(@past_year)
    assign_teacher_to!(@current_year)
  end

  test 'backfills legacy assignments using configured Macau boundaries rather than September first' do
    before_current = create_legacy_assignment!('Past boundary', macau_time(2026, 8, 14, 23, 59, 59))
    current_start = create_legacy_assignment!('Current start', macau_time(2026, 8, 15, 0, 0, 0))
    current_end = create_legacy_assignment!('Current end', macau_time(2027, 7, 20, 23, 59, 59))
    after_current = create_legacy_assignment!('After current', macau_time(2027, 7, 21, 0, 0, 0))

    run_backfill!

    assert_equal @past_year.id, before_current.reload.school_academic_year_id
    assert_equal @current_year.id, current_start.reload.school_academic_year_id
    assert_equal @current_year.id, current_end.reload.school_academic_year_id
    assert_nil after_current.reload.school_academic_year_id
  end

  test 'prefers the only active year when legacy date ranges overlap' do
    overlapping_archived_year = SchoolAcademicYear.new(
      school: @school,
      name: 'Legacy overlap',
      start_date: @current_year.start_date,
      end_date: @current_year.end_date,
      status: :archived,
      meta: {}
    )
    overlapping_archived_year.save!(validate: false)
    assign_teacher_to!(overlapping_archived_year)
    assignment = create_legacy_assignment!('Overlapping ranges', macau_time(2026, 10, 10, 12, 0, 0))

    run_backfill!

    assert_equal @current_year.id, assignment.reload.school_academic_year_id
  end

  private

  def create_year!(name:, start_date:, end_date:, status:)
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
      email: "migration-academic-year-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: 'Migration Academic Year Teacher',
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

  def create_legacy_assignment!(title, created_at)
    EssayAssignment.create!(
      general_user: @teacher,
      school_academic_year: nil,
      topic: title,
      assignment: title,
      title:,
      category: 'essay',
      rubric: {
        'name' => 'Migration Test Rubric',
        'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
      },
      meta: {},
      created_at:,
      updated_at: created_at
    )
  end

  def run_backfill!
    AddSchoolAcademicYearToEssayAssignments.new.send(:backfill_school_academic_years!)
  end

  def macau_time(year, month, day, hour, minute, second)
    ActiveSupport::TimeZone['Asia/Macau'].local(year, month, day, hour, minute, second)
  end
end
