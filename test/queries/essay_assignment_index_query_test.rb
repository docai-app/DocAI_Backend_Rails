# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentIndexQueryTest < ActiveSupport::TestCase
  self.fixture_table_names = []

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
    comprehension_assignment = EssayAssignment.create!(
      general_user: @owner,
      topic: 'Comprehension Topic',
      assignment: 'Comprehension Assignment',
      title: 'Comprehension Title',
      category: 'comprehension',
      rubric: default_rubric,
      meta: {}
    )

    EssayAssignmentShare.create!(
      essay_assignment: comprehension_assignment,
      shared_with_general_user: @recipient,
      shared_by_general_user: @owner,
      school: @context[:school],
      school_academic_year: @context[:year],
      status: :active
    )

    result = EssayAssignmentIndexQuery.new(user: @recipient, category: 'essay').call
    ids = result.assignments.map(&:id)

    assert_includes ids, @owned_assignment.id
    assert_not_includes ids, comprehension_assignment.id
  end

  test 'filters assignments by search keyword' do
    result = EssayAssignmentIndexQuery.new(user: @recipient, search: 'Owned').call
    ids = result.assignments.map(&:id)

    assert_includes ids, @owned_assignment.id
    assert_not_includes ids, @shared_assignment.id
  end

  test 'filters owned and shared assignments before pagination by academic year range' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @shared_assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    historical_at = 18.months.ago.change(hour: 12)
    historical_owned = create_assignment!(
      user: @recipient,
      title: 'Historical Owned Title'
    )
    historical_shared = create_assignment!(
      user: @owner,
      title: 'Historical Shared Title'
    )
    [historical_owned, historical_shared].each do |assignment|
      assignment.update_columns(created_at: historical_at, updated_at: historical_at)
    end

    EssayAssignmentShareService.sync_shares!(
      assignment: historical_shared,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    result = EssayAssignmentIndexQuery.new(
      user: @recipient,
      created_at_range: historical_at.beginning_of_day..historical_at.end_of_day,
      page: 1,
      per: 1
    ).call
    ids = result.assignments.map(&:id)

    assert_equal 2, result.meta[:total_count]
    assert_equal 2, result.meta[:total_pages]
    assert_equal 1, ids.size
    assert_includes [historical_owned.id, historical_shared.id], ids.first
    assert_not_includes ids, @owned_assignment.id
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

    owner = create_teacher!(year: year, nickname: 'Owner', features: %w[essay comprehension])
    recipient = create_teacher!(year: year, nickname: 'Recipient', features: %w[essay])

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
      school: school,
      year: year,
      owner: owner,
      recipient: recipient,
      owned_assignment: owned_assignment,
      shared_assignment: shared_assignment
    }
  end

  def create_teacher!(year:, nickname:, features:)
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

  def create_assignment!(user:, title:)
    EssayAssignment.create!(
      general_user: user,
      topic: title,
      assignment: title,
      title:,
      category: 'essay',
      rubric: default_rubric,
      meta: {}
    )
  end

  def default_rubric
    {
      'name' => 'Test Rubric',
      'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
    }
  end
end
