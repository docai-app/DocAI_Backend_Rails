# frozen_string_literal: true

require 'test_helper'

class AssignedEssayAssignmentAccessTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @school = School.create!(
      name: "Assigned Access School #{SecureRandom.hex(4)}",
      code: "assigned-access-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    @academic_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2025-2026',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active,
      meta: {}
    )
    @teacher = create_user!('teacher', %w[sentence_builder])
    @student = create_user!('student', %w[essay])
    StudentEnrollment.create!(
      general_user: @student,
      school_academic_year: @academic_year,
      class_name: 'P1A',
      class_number: '1',
      status: :active,
      meta: {}
    )
    @assignment = EssayAssignment.create!(
      general_user: @teacher,
      topic: 'Sentence Builder Topic',
      assignment: 'Build the sentence',
      title: 'Sentence Builder Assignment',
      category: 'sentence_builder',
      rubric: default_rubric,
      meta: {}
    )
    @student_token = sign_in_token(@student)
  end

  test 'student without the feature cannot open an unassigned assignment' do
    get "/api/v1/essay_assignments/#{@assignment.code}/show_only.json",
        headers: auth_headers(@student_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'Access denied', body['error']
  end

  test 'student can open an explicitly assigned assignment when feature list changed' do
    assign_to_student!

    get '/api/v1/essay_assignments/my_assignments',
        params: { status: 'assigned,overdue' },
        headers: auth_headers(@student_token),
        as: :json

    assert_response :success
    pending_body = JSON.parse(response.body)
    pending_assignment_ids = pending_body.fetch('assignments').map do |item|
      item.dig('essay_assignment', 'id')
    end
    assert_includes pending_assignment_ids, @assignment.id

    get "/api/v1/essay_assignments/#{@assignment.code}/show_only.json",
        headers: auth_headers(@student_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal @assignment.id, body.dig('essay_assignment', 'id')
    assert_equal 'sentence_builder', body.dig('essay_assignment', 'category')
  end

  private

  def create_user!(role, features)
    user = GeneralUser.create!(
      email: "#{role}-assigned-access-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: role.titleize,
      meta: { 'aienglish_role' => role, 'aienglish_features_list' => features },
      konnecai_tokens: {}
    )
    user.create_energy(value: 100) unless user.energy
    user
  end

  def assign_to_student!
    distribution = AssignmentDistribution.new(
      essay_assignment: @assignment,
      school: @school,
      school_academic_year: @academic_year,
      distribution_type: :individual,
      target_student: @student,
      deadline: 1.month.from_now,
      status: :active,
      meta: {}
    )
    distribution.save!(validate: false)

    AssignmentStudentAssignment.find_or_create_by!(
      essay_assignment: @assignment,
      general_user: @student
    ) do |student_assignment|
      student_assignment.assignment_distribution = distribution
      student_assignment.deadline = distribution.deadline
      student_assignment.status = :assigned
      student_assignment.meta = {}
    end
  end

  def default_rubric
    {
      'name' => 'Test Rubric',
      'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
    }
  end

  def sign_in_token(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    "Bearer #{token}"
  end

  def auth_headers(token)
    { 'Authorization' => token }
  end
end
