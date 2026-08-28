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

  test 'school_teacher_candidates excludes teachers only assigned to archived years' do
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
    legacy_teacher.update!(school_id: @school.id)

    payload = EssayAssignmentShareService.school_teacher_candidates(
      school: @school,
      exclude_user: @owner
    )

    teacher_ids = payload[:teachers].map { |teacher| teacher[:id] }
    assert_includes teacher_ids, @recipient.id
    assert_not_includes teacher_ids, legacy_teacher.id
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

  test 'sync_shares rejects new recipients from archived years without changing historical membership checks' do
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

    error = assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(
        assignment: @assignment,
        actor: @owner,
        teacher_ids: [legacy_teacher.id]
      )
    end

    assert error.details.any? { |item| item[:error] == 'not_current_school_teacher' }
    assert_not @assignment.shared_with?(legacy_teacher)
  end

  test 'locked and nonactive current teachers are excluded with their departments' do
    @recipient.update!(locked_at: Time.current)
    @recipient.teacher_assignments.first.update!(department: 'Locked Department')
    @other_teacher.teacher_assignments.first.update!(status: :transferred, department: 'Old Department')

    payload = EssayAssignmentShareService.school_teacher_candidates(school: @school, exclude_user: @owner)
    assert_empty payload[:teachers]
    assert_empty payload[:departments]
    assert_not_includes EssayAssignmentShareService.departments_for_school(@school), 'Locked Department'
    assert_not_includes EssayAssignmentShareService.departments_for_school(@school), 'Old Department'
  end

  test 'resigned and sabbatical teachers cannot be new recipients even with direct school pointers' do
    %i[resigned sabbatical transferred].each do |status|
      @recipient.update!(school_id: @school.id)
      @recipient.teacher_assignments.first.update!(status: status)
      assert_not_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), @recipient.id
      assert_raises(EssayAssignmentShareService::ShareError) do
        EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
      end
    end
    assert_empty @assignment.essay_assignment_shares
  end

  test 'locked current teacher is rejected on write without revoking other shares' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@other_teacher.id])
    @recipient.update!(locked_at: Time.current)
    error = assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    end
    assert error.details.any? { |item| item[:error] == 'teacher_locked' }
    assert @assignment.shared_with?(@other_teacher)
    assert_not @assignment.shared_with?(@recipient)
  end

  test 'unlocking a current teacher restores candidate eligibility' do
    @recipient.update!(locked_at: Time.current)
    assert_not_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), @recipient.id
    @recipient.update!(locked_at: nil)
    assert_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), @recipient.id
    result = EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    assert result.success?
  end

  test 'candidate department comes from current year rather than recently edited old membership' do
    old_year = SchoolAcademicYear.create!(school: @school, name: '2023', start_date: Date.new(2023, 1, 1), end_date: Date.new(2023, 12, 31), status: :archived, meta: {})
    TeacherAssignment.create!(general_user: @recipient, school_academic_year: old_year, department: 'Old Department', position: 'Former Position', status: :active, meta: {})
    payload = EssayAssignmentShareService.school_teacher_candidates(school: @school, exclude_user: @owner)
    rows = payload[:teachers].select { |row| row[:id] == @recipient.id }
    assert_equal 1, rows.size
    assert_equal 'English', rows.first[:department]
    assert_equal 'Teacher', rows.first[:position]
    assert_not_includes payload[:departments], 'Old Department'
  end

  test 'missing current academic year does not fall back to archived or direct school teachers' do
    @context[:year].update!(status: :archived)
    @recipient.update!(school_id: @school.id)
    payload = EssayAssignmentShareService.school_teacher_candidates(school: @school, exclude_user: @owner)
    assert_empty payload[:teachers]
    assert_empty payload[:departments]
    assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    end
  end

  test 'current school year flag governs sharing even before its start date' do
    @context[:year].update!(start_date: Date.current + 10.days, end_date: Date.current + 1.year)
    assert_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), @recipient.id
  end

  test 'same email domain in a different school is not sufficient for sharing' do
    other_school = School.create!(name: 'Other School', code: "other-share-#{SecureRandom.hex(4)}", meta: {})
    other_year = SchoolAcademicYear.create!(school: other_school, name: '2025', start_date: Date.current.beginning_of_year, end_date: Date.current.end_of_year, status: :active, meta: {})
    other = create_teacher!(school: other_school, year: other_year, nickname: 'Other School Teacher', features: %w[essay])
    other.update!(school_id: @school.id)
    assert_not_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), other.id
    assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [other.id])
    end
  end

  test 'non teacher account with an old teacher assignment is not a candidate' do
    @recipient.update!(meta: { 'aienglish_role' => 'student', 'aienglish_features_list' => %w[essay] })
    assert_not_includes EssayAssignmentShareService.school_teachers_relation(school: @school).pluck(:id), @recipient.id
  end

  test 'existing historical shares can be retained and removed but not reactivated for ineligible teachers' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    @recipient.update!(locked_at: Time.current)
    @recipient.teacher_assignments.first.update!(status: :transferred)
    result = EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id, @other_teacher.id])
    assert result.success?
    assert @assignment.shared_with?(@recipient)
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@other_teacher.id])
    assert_not @assignment.shared_with?(@recipient)
    assert_raises(EssayAssignmentShareService::ShareError) do
      EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    end
    assert @assignment.shared_with?(@other_teacher)
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

  test 'candidate loading uses two bounded queries regardless of teacher count and no full account objects' do
    # Warm schema metadata, but disable query caching for the measured calls.
    GeneralUser.columns
    TeacherAssignment.columns
    SchoolAcademicYear.columns
    small = measure_candidate_queries
    30.times do |index|
      create_teacher!(school: @school, year: @context[:year], nickname: "Teacher #{index}", features: %w[essay])
    end
    large = measure_candidate_queries

    assert_equal 2, small[:teachers].length
    assert_equal 32, large[:teachers].length
    assert_operator small[:queries].length, :<=, 2
    assert_equal small[:queries].length, large[:queries].length
    assert_empty large[:account_instantiations]
    assert large[:queries].any? { |sql| sql.include?('teacher_assignments') && sql.include?('general_users') }
    assert large[:teachers].all? { |row| row.keys.sort == %i[id email nickname department position].sort }
  end

  test 'candidate results reflect locking and unlocking without a server roster cache' do
    assert_includes candidate_ids, @recipient.id
    @recipient.update!(locked_at: Time.current)
    assert_not_includes candidate_ids, @recipient.id
    @recipient.update!(locked_at: nil)
    assert_includes candidate_ids, @recipient.id
  end

  private

  def candidate_ids
    EssayAssignmentShareService.school_teacher_candidates(school: @school, exclude_user: @owner)[:teachers].map { |row| row[:id] }
  end

  def measure_candidate_queries
    queries = []
    account_instantiations = []
    sql_callback = lambda do |*, event|
      queries << event[:sql] if event[:sql].match?(/\ASELECT/i) && event[:name] != 'SCHEMA'
    end
    instance_callback = lambda do |*, event|
      account_instantiations << event if %w[GeneralUser TeacherAssignment].include?(event[:class_name])
    end
    teachers = nil
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql_callback, 'sql.active_record') do
        ActiveSupport::Notifications.subscribed(instance_callback, 'instantiation.active_record') do
          teachers = EssayAssignmentShareService.school_teacher_candidates(school: @school, exclude_user: @owner)[:teachers]
        end
      end
    end
    { teachers: teachers, queries: queries, account_instantiations: account_instantiations }
  end

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
