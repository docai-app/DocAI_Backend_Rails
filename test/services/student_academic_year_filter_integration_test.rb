# frozen_string_literal: true

require 'test_helper'

class StudentAcademicYearFilterIntegrationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @school = School.create!(
      name: "Student Year Filter School #{SecureRandom.hex(4)}",
      code: "student-year-filter-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    @current_year = create_academic_year!(
      name: 'Current Year',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active
    )
    @past_year = create_academic_year!(
      name: 'Past Year',
      start_date: Date.current.prev_year.beginning_of_year,
      end_date: Date.current.prev_year.end_of_year,
      status: :archived
    )
    @student = create_student!
    create_enrollment!(@current_year, class_name: 'F2A', class_number: '18')
    create_enrollment!(@past_year, class_name: 'F1A', class_number: '12')
  end

  test 'filters submitted work by snapshot with created at fallback' do
    current_grading = create_grading!('Current submission')
    current_grading.update_columns(
      submission_academic_year_id: @current_year.id,
      created_at: time_in(@current_year)
    )

    past_grading = create_grading!('Past submission')
    past_grading.update_columns(
      submission_academic_year_id: @past_year.id,
      created_at: time_in(@current_year)
    )

    legacy_past_grading = create_grading!('Legacy past submission')
    legacy_past_grading.update_columns(
      submission_academic_year_id: nil,
      created_at: time_in(@past_year)
    )

    current_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: @current_year.id
    )
    past_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: @past_year.id
    )
    all_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: StudentAcademicYearFilter::ALL_ACADEMIC_YEARS_ID
    )

    assert_equal [current_grading.id], filtered_grading_ids(current_result)
    assert_equal [past_grading.id, legacy_past_grading.id].sort, filtered_grading_ids(past_result).sort
    assert_equal [current_grading.id, past_grading.id, legacy_past_grading.id].sort,
                 filtered_grading_ids(all_result).sort
  end

  test 'filters unsubmitted work by assignment time and submitted work by submission year' do
    current_unsubmitted = create_student_assignment!('Current unsubmitted', time_in(@current_year))
    past_unsubmitted = create_student_assignment!('Past unsubmitted', time_in(@past_year))

    submitted_assignment = create_assignment!('Submitted in past')
    submitted_grading = create_grading!('Submitted in past', assignment: submitted_assignment)
    submitted_grading.update_columns(
      submission_academic_year_id: @past_year.id,
      created_at: time_in(@past_year)
    )
    submitted = create_student_assignment!(
      'Submitted in past',
      time_in(@current_year),
      assignment: submitted_assignment
    )

    current_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: @current_year.id
    )
    past_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: @past_year.id
    )
    all_result = StudentAcademicYearFilter.resolve(
      user: @student,
      academic_year_id: StudentAcademicYearFilter::ALL_ACADEMIC_YEARS_ID
    )

    assert_equal [current_unsubmitted.id], filtered_assignment_ids(current_result)
    assert_equal [past_unsubmitted.id, submitted.id].sort, filtered_assignment_ids(past_result).sort
    assert_equal [current_unsubmitted.id, past_unsubmitted.id, submitted.id].sort,
                 filtered_assignment_ids(all_result).sort
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

  def create_student!
    GeneralUser.create!(
      email: "student-year-filter-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: 'Student Year Filter',
      meta: { 'aienglish_role' => 'student', 'aienglish_features_list' => ['essay'] },
      konnecai_tokens: {}
    )
  end

  def create_enrollment!(academic_year, class_name:, class_number:)
    StudentEnrollment.create!(
      general_user: @student,
      school_academic_year: academic_year,
      class_name:,
      class_number:,
      status: :active,
      meta: {}
    )
  end

  def create_assignment!(title)
    EssayAssignment.create!(
      general_user: @student,
      topic: title,
      assignment: title,
      title:,
      category: 'essay',
      rubric: {
        'name' => 'Test Rubric',
        'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
      },
      meta: {}
    )
  end

  def create_grading!(title, assignment: nil)
    assignment ||= create_assignment!(title)
    grading = EssayGrading.create!(
      essay_assignment: assignment,
      general_user: @student,
      topic: title,
      essay: 'Test response',
      status: :draft,
      grading: {},
      general_context: {},
      revised_essay: {},
      meta: {}
    )
    grading.update_columns(status: EssayGrading.statuses.fetch('pending'))
    grading
  end

  def create_student_assignment!(title, assigned_at, assignment: nil)
    assignment ||= create_assignment!(title)
    distribution = AssignmentDistribution.new(
      essay_assignment: assignment,
      school_academic_year: @current_year,
      school: @school,
      distribution_type: :individual,
      target_student: nil,
      deadline: 1.month.from_now,
      status: :active,
      meta: {}
    )
    distribution.save!(validate: false)

    student_assignment = AssignmentStudentAssignment.create!(
      essay_assignment: assignment,
      general_user: @student,
      assignment_distribution: distribution,
      deadline: distribution.deadline,
      status: :assigned,
      meta: {}
    )
    student_assignment.update_columns(created_at: assigned_at, updated_at: assigned_at)
    student_assignment
  end

  def time_in(academic_year)
    ActiveSupport::TimeZone['Asia/Hong_Kong'].local(
      academic_year.start_date.year,
      academic_year.start_date.month,
      academic_year.start_date.day
    ) + 1.month
  end

  def filtered_grading_ids(result)
    StudentAcademicYearFilter.filter_gradings(scope: @student.essay_gradings, result:).pluck(:id)
  end

  def filtered_assignment_ids(result)
    StudentAcademicYearFilter.filter_assignments(
      scope: @student.assignment_student_assignments,
      result:,
      user: @student
    ).pluck(:id)
  end
end
