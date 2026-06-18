# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentShareTest < ActiveSupport::TestCase
  setup do
    @context = build_share_test_context
    @owner = @context[:owner]
    @recipient = @context[:recipient]
    @assignment = @context[:assignment]
    @school = @context[:school]
  end

  test 'creates active share for same school teacher' do
    share = EssayAssignmentShare.create!(
      essay_assignment: @assignment,
      owner_general_user: @owner,
      shared_with_general_user: @recipient,
      shared_by_general_user: @owner,
      school: @school,
      status: :active
    )

    assert share.active?
    assert_equal @owner.id, share.owner_general_user_id
  end

  test 'cannot share assignment with self' do
    share = EssayAssignmentShare.new(
      essay_assignment: @assignment,
      owner_general_user: @owner,
      shared_with_general_user: @owner,
      shared_by_general_user: @owner,
      school: @school,
      status: :active
    )

    assert_not share.valid?
    assert_includes share.errors[:shared_with_general_user_id], 'cannot share assignment with yourself'
  end

  test 'revoke marks share as revoked' do
    share = EssayAssignmentShare.create!(
      essay_assignment: @assignment,
      owner_general_user: @owner,
      shared_with_general_user: @recipient,
      shared_by_general_user: @owner,
      school: @school,
      status: :active
    )

    share.revoke!

    assert share.revoked?
    assert share.revoked_at.present?
  end

  private

  def build_share_test_context
    school = School.create!(
      name: "Share Test School #{SecureRandom.hex(4)}",
      code: "share-#{SecureRandom.hex(4)}",
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

    { school: school, year: year, owner: owner, recipient: recipient, assignment: assignment }
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
end
