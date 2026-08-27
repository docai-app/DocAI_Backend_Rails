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
    @past_academic_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2024-2025',
      start_date: Date.current.prev_year.beginning_of_year,
      end_date: Date.current.prev_year.end_of_year,
      status: :archived,
      meta: {}
    )
    @teacher = create_user!('teacher', %w[sentence_builder])
    @student = create_user!('student', %w[essay])
    [@academic_year, @past_academic_year].each do |academic_year|
      TeacherAssignment.create!(
        general_user: @teacher,
        school_academic_year: academic_year,
        department: 'English',
        position: 'Teacher',
        status: :active,
        meta: {}
      )
    end
    StudentEnrollment.create!(
      general_user: @student,
      school_academic_year: @academic_year,
      class_name: 'P1A',
      class_number: '1',
      status: :active,
      meta: {}
    )
    StudentEnrollment.create!(
      general_user: @student,
      school_academic_year: @past_academic_year,
      class_name: 'P0A',
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

  test 'student assignments paginate in the database with year-scoped totals' do
    assign_to_student!
    2.times do |index|
      assignment = EssayAssignment.create!(
        general_user: @teacher,
        school_academic_year: @academic_year,
        topic: "Pagination Topic #{index}",
        assignment: "Pagination Assignment #{index}",
        title: "Pagination Assignment #{index}",
        category: 'sentence_builder',
        rubric: default_rubric,
        meta: {}
      )
      assign_to_student!(assignment: assignment)
    end

    get '/api/v1/essay_assignments/my_assignments',
        params: { status: 'assigned,overdue', page: 2, per_page: 1 },
        headers: auth_headers(@student_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch('assignments').size
    assert_equal 2, body.dig('meta', 'pagination', 'current_page')
    assert_equal 3, body.dig('meta', 'pagination', 'total_pages')
    assert_equal 3, body.dig('meta', 'pagination', 'total_count')
    assert_equal @academic_year.id.to_s, body.dig('meta', 'academic_year', 'id').to_s
  end

  test 'distribution inherits the assignment year so a newly created past assignment stays out of current' do
    past_assignment = EssayAssignment.create!(
      general_user: @teacher,
      school_academic_year: @past_academic_year,
      topic: 'Past year topic created today',
      assignment: 'Past year assignment created today',
      title: 'Past year assignment created today',
      category: 'sentence_builder',
      rubric: default_rubric,
      meta: {}
    )
    teacher_token = sign_in_token(@teacher)

    get '/api/v1/essay_assignments/distribution_options',
        params: { school_academic_year_id: @past_academic_year.id },
        headers: auth_headers(teacher_token),
        as: :json

    assert_response :success
    option_student_ids = response.parsed_body.dig('options', 'students').map { |student| student['id'] }
    assert_includes option_student_ids, @student.id

    post "/api/v1/essay_assignments/#{past_assignment.id}/distributions",
         params: {
           distribution: {
             distribution_type: 'individual',
             target_student_id: @student.id,
             deadline: 1.month.from_now.iso8601
           }
         },
         headers: auth_headers(teacher_token),
         as: :json

    assert_response :created, response.body
    distribution = AssignmentDistribution.find(response.parsed_body.dig('distribution', 'id'))
    assert_equal @past_academic_year.id, distribution.school_academic_year_id

    get "/api/v1/essay_assignments/#{past_assignment.id}/statistics",
        headers: auth_headers(teacher_token),
        as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.dig('statistics', 'total_assigned')
    assert_equal 'P0A', response.parsed_body.dig('statistics', 'students', 0, 'class_name')

    current_ids = student_assignment_ids_for(@academic_year.id)
    past_ids = student_assignment_ids_for(@past_academic_year.id)
    all_ids = student_assignment_ids_for('all')

    assert_not_includes current_ids, past_assignment.id
    assert_includes past_ids, past_assignment.id
    assert_includes all_ids, past_assignment.id
  end

  test 'teacher cannot distribute an assignment belonging to another school' do
    other_school = School.create!(
      name: "Other Distribution School #{SecureRandom.hex(4)}",
      code: "other-distribution-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    other_year = SchoolAcademicYear.create!(
      school: other_school,
      name: 'Other Current Year',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active,
      meta: {}
    )
    other_teacher = create_user!('teacher', %w[sentence_builder])
    TeacherAssignment.create!(
      general_user: other_teacher,
      school_academic_year: other_year,
      department: 'English',
      position: 'Teacher',
      status: :active,
      meta: {}
    )
    other_assignment = EssayAssignment.create!(
      general_user: other_teacher,
      school_academic_year: other_year,
      topic: 'Other school topic',
      assignment: 'Other school assignment',
      title: 'Other school assignment',
      category: 'sentence_builder',
      rubric: default_rubric,
      meta: {}
    )

    get '/api/v1/essay_assignments/distribution_options',
        params: { school_academic_year_id: other_year.id },
        headers: auth_headers(sign_in_token(@teacher)),
        as: :json

    assert_response :not_found

    get "/api/v1/essay_assignments/#{other_assignment.id}/statistics",
        headers: auth_headers(sign_in_token(@teacher)),
        as: :json

    assert_response :forbidden

    post "/api/v1/essay_assignments/#{other_assignment.id}/distributions",
         params: {
           distribution: {
             distribution_type: 'individual',
             target_student_id: @student.id,
             deadline: 1.month.from_now.iso8601
           }
         },
         headers: auth_headers(sign_in_token(@teacher)),
         as: :json

    assert_response :forbidden
    assert_empty other_assignment.assignment_distributions
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

  def assign_to_student!(assignment: @assignment)
    distribution = AssignmentDistribution.new(
      essay_assignment: assignment,
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
      essay_assignment: assignment,
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

  def student_assignment_ids_for(academic_year_id)
    get '/api/v1/essay_assignments/my_assignments',
        params: {
          status: 'assigned,overdue',
          school_academic_year_id: academic_year_id,
          per_page: 50
        },
        headers: auth_headers(@student_token),
        as: :json

    assert_response :success
    response.parsed_body.fetch('assignments').map { |item| item.dig('essay_assignment', 'id') }
  end
end
