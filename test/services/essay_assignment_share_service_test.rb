# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentShareServiceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @context = build_share_test_context
    @owner = @context[:owner]
    @recipient = @context[:recipient]
    @other_teacher = @context[:other_teacher]
    @assignment = @context[:assignment]
    @school = @context[:school]
  end

  test 'sync_shares creates and revokes shares for owner' do
    result = EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    assert result.success?
    assert_equal 1, @assignment.active_essay_assignment_shares.count
    assert @assignment.shared_with?(@recipient)

    result = EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@other_teacher.id]
    )

    assert result.success?
    assert_not @assignment.shared_with?(@recipient)
    assert @assignment.shared_with?(@other_teacher)
  end

  test 'sync_shares rejects non owner actor' do
    error = assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(
        assignment: @assignment,
        actor: @recipient,
        teacher_ids: [@other_teacher.id]
      )
    end

    assert_match(/owner/i, error.message)
  end

  test 'sync_shares rejects teacher without category permission' do
    teacher_without_essay = create_teacher!(
      school: @school,
      year: @context[:year],
      nickname: 'Comprehension Teacher',
      features: %w[comprehension]
    )

    error = assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(
        assignment: @assignment,
        actor: @owner,
        teacher_ids: [teacher_without_essay.id]
      )
    end

    assert error.details.any? { |item| item[:error] == EssayAssignmentShareService::INELIGIBLE_MISSING_CATEGORY }
  end

  test 'school_teacher_candidates returns same school teachers regardless of academic year filter' do
    older_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2023',
      start_date: Date.new(2023, 1, 1),
      end_date: Date.new(2023, 12, 31),
      status: :archived,
      meta: {}
    )
    legacy_teacher = create_teacher!(
      school: @school,
      year: older_year,
      nickname: 'Legacy Teacher',
      features: %w[essay]
    )

    payload = EssayAssignmentShareService.school_teacher_candidates(
      school: @school,
      exclude_user: @owner
    )

    teacher_ids = payload[:teachers].map { |teacher| teacher[:id] }
    assert_includes teacher_ids, @recipient.id
    assert_includes teacher_ids, legacy_teacher.id
    assert_not_includes teacher_ids, @owner.id
  end

  test 'school_teacher_candidates returns all same school teachers for frontend filtering' do
    science_teacher = create_teacher!(
      school: @school,
      year: @context[:year],
      nickname: 'Science Teacher',
      features: %w[essay],
      department: 'Science'
    )

    payload = EssayAssignmentShareService.school_teacher_candidates(
      school: @school,
      exclude_user: @owner
    )

    teacher_ids = payload[:teachers].map { |teacher| teacher[:id] }
    assert_includes teacher_ids, @recipient.id
    assert_includes teacher_ids, science_teacher.id
    assert_not_includes teacher_ids, @owner.id
    assert_not payload.key?(:meta)
  end

  test 'sync_shares accepts teacher from archived academic year when listed in school candidates' do
    older_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2023',
      start_date: Date.new(2023, 1, 1),
      end_date: Date.new(2023, 12, 31),
      status: :archived,
      meta: {}
    )
    legacy_teacher = create_teacher!(
      school: @school,
      year: older_year,
      nickname: 'Legacy Teacher',
      features: %w[essay]
    )

    assert EssayAssignmentShareService.same_school_teacher?(school: @school, teacher: legacy_teacher)

    result = EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [legacy_teacher.id]
    )

    assert result.success?
    assert @assignment.shared_with?(legacy_teacher)
  end

  test 'assignment access helpers distinguish owner and shared recipient' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    assert @assignment.owned_by?(@owner)
    assert @assignment.can_share?(@owner)
    assert @assignment.can_delete?(@owner)

    assert @assignment.shared_with?(@recipient)
    assert_equal 'shared', @assignment.access_type_for(@recipient)
    assert_not @assignment.can_share?(@recipient)
    assert @assignment.can_assign_to_students?(@recipient)
    assert_equal 'Shared by Owner Teacher', @assignment.shared_by_label_for(@recipient)
  end

  private

  def build_share_test_context
    school = School.create!(
      name: "Share Service School #{SecureRandom.hex(4)}",
      code: "share-svc-#{SecureRandom.hex(4)}",
      meta: {}
    )
    year = SchoolAcademicYear.create!(
      school: school,
      name: '2025',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active,
      meta: {}
    )

    owner = create_teacher!(school: school, year: year, nickname: 'Owner Teacher', features: %w[essay])
    recipient = create_teacher!(school: school, year: year, nickname: 'Recipient Teacher', features: %w[essay])
    other_teacher = create_teacher!(school: school, year: year, nickname: 'Other Teacher', features: %w[essay])

    assignment = EssayAssignment.create!(
      general_user: owner,
      topic: 'Topic',
      assignment: 'Assignment',
      title: 'Title',
      category: 'essay',
      rubric: {
        'name' => 'Test Rubric',
        'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
      },
      meta: {}
    )

    {
      school: school,
      year: year,
      owner: owner,
      recipient: recipient,
      other_teacher: other_teacher,
      assignment: assignment
    }
  end

  def create_teacher!(school:, year:, nickname:, features:, department: 'English')
    teacher = GeneralUser.create!(
      email: "teacher-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: nickname,
      meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => features },
      konnecai_tokens: {}
    )
    teacher.create_energy(value: 100) unless teacher.energy
    TeacherAssignment.create!(
      general_user: teacher,
      school_academic_year: year,
      department: department,
      position: 'Teacher',
      status: :active,
      meta: {}
    )
    teacher
  end
end
