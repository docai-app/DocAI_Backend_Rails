# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentIndexQueryTest < ActiveSupport::TestCase
  setup do
    @context = build_index_query_context
    @owner = @context[:owner]
    @recipient = @context[:recipient]
    @owned_assignment = @context[:owned_assignment]
    @shared_assignment = @context[:shared_assignment]
  end

  test 'returns owned and shared assignments without duplicates' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @shared_assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    result = EssayAssignmentIndexQuery.new(user: @recipient).call
    ids = result.assignments.map(&:id)

    assert_includes ids, @owned_assignment.id
    assert_includes ids, @shared_assignment.id
    assert_equal ids.uniq.size, ids.size
  end

  test 'filters shared assignments by category permission' do
    listening_assignment = EssayAssignment.create!(
      general_user: @owner,
      topic: 'Listening Topic',
      assignment: 'Listening Assignment',
      title: 'Listening Title',
      category: 'listening',
      rubric: default_rubric,
      meta: {}
    )

    EssayAssignmentShareService.sync_shares!(
      assignment: listening_assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    result = EssayAssignmentIndexQuery.new(user: @recipient, category: 'essay').call
    ids = result.assignments.map(&:id)

    assert_includes ids, @owned_assignment.id
    assert_not_includes ids, listening_assignment.id
  end

  test 'filters assignments by search keyword' do
    result = EssayAssignmentIndexQuery.new(user: @recipient, search: 'Owned').call
    ids = result.assignments.map(&:id)

    assert_includes ids, @owned_assignment.id
    assert_not_includes ids, @shared_assignment.id
  end

  private

  def build_index_query_context
    school = School.create!(
      name: "Index Query School #{SecureRandom.hex(4)}",
      code: "index-query-#{SecureRandom.hex(4)}",
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

    owner = create_teacher!(school: school, year: year, nickname: 'Owner', features: %w[essay listening])
    recipient = create_teacher!(school: school, year: year, nickname: 'Recipient', features: %w[essay])

    owned_assignment = EssayAssignment.create!(
      general_user: recipient,
      topic: 'Owned Topic',
      assignment: 'Owned Assignment',
      title: 'Owned Title',
      category: 'essay',
      rubric: default_rubric,
      meta: {}
    )

    shared_assignment = EssayAssignment.create!(
      general_user: owner,
      topic: 'Shared Topic',
      assignment: 'Shared Assignment',
      title: 'Shared Title',
      category: 'essay',
      rubric: default_rubric,
      meta: {}
    )

    {
      owner: owner,
      recipient: recipient,
      owned_assignment: owned_assignment,
      shared_assignment: shared_assignment
    }
  end

  def create_teacher!(school:, year:, nickname:, features:)
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
      department: 'English',
      position: 'Teacher',
      status: :active,
      meta: {}
    )
    teacher
  end

  def default_rubric
    {
      'name' => 'Test Rubric',
      'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
    }
  end
end
