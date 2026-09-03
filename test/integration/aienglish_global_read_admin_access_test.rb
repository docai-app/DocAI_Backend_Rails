# frozen_string_literal: true

require 'test_helper'

class AienglishGlobalReadAdminAccessTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'

    @school = School.create!(
      name: "Global Read Admin School #{SecureRandom.hex(4)}",
      code: "global-read-admin-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    @academic_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2024-2025',
      start_date: Date.new(2024, 8, 1),
      end_date: Date.new(2025, 7, 31),
      status: :archived,
      meta: {}
    )
    @current_academic_year = SchoolAcademicYear.create!(
      school: @school,
      name: '2026-2027',
      start_date: Date.new(2026, 8, 1),
      end_date: Date.new(2027, 7, 31),
      status: :active,
      meta: {}
    )

    @owner = create_user!('assignment-owner', 'owner@example.test')
    @global_read_admin = create_user!('global-read-admin', 'teacher@docai.net')
    @unrelated_teacher = create_user!('unrelated-teacher', 'unrelated@example.test')
    @share_recipient = create_user!('share-recipient', 'share-recipient@example.test')
    @student = create_user!('student', 'student@example.test', role: 'student')

    TeacherAssignment.create!(
      general_user: @share_recipient,
      school_academic_year: @current_academic_year,
      department: 'English',
      position: 'Teacher',
      status: :active,
      meta: {}
    )
    StudentEnrollment.create!(
      general_user: @student,
      school_academic_year: @academic_year,
      class_name: '3B',
      class_number: '8',
      status: :active,
      meta: {}
    )

    @assignment = EssayAssignment.create!(
      general_user: @owner,
      school_academic_year: @academic_year,
      topic: 'Historical assignment topic',
      assignment: 'Historical assignment instructions',
      title: 'Historical assignment',
      category: 'essay',
      answer_visible: false,
      rubric: {
        'name' => 'Test Rubric',
        'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
      },
      meta: { 'score_visible' => false }
    )
    @grading = EssayGrading.create!(
      essay_assignment: @assignment,
      general_user: @student,
      topic: @assignment.topic,
      essay: 'Student response',
      status: :draft,
      grading: {},
      general_context: {},
      revised_essay: {},
      meta: {}
    )
    @grading.update_columns(status: EssayGrading.statuses.fetch('graded'), updated_at: Time.current)
  end

  test 'global read admin can inspect any assignment without an academic year parameter' do
    get "/api/v1/essay_assignments/#{@assignment.id}.json",
        headers: auth_headers(sign_in_token(@global_read_admin)),
        as: :json

    assert_response :ok, response.body
    assert_equal @assignment.id, response.parsed_body.dig('essay_assignment', 'id')
    assert_equal @academic_year.id.to_s,
                 response.parsed_body.dig('essay_assignment', 'school_academic_year_id').to_s
    assignment_json = response.parsed_body.fetch('essay_assignment')
    assert_equal 'admin', assignment_json['access_type']
    assert_equal true, assignment_json['can_edit']
    assert_equal true, assignment_json['can_delete']
    assert_equal true, assignment_json['can_share']
    assert_equal true, assignment_json['can_assign_to_students']
    assert_equal true, assignment_json['can_duplicate']
    assert_equal true, assignment_json['can_release_scores']

    get "/api/v1/essay_assignments/#{@assignment.id}/read.json",
        headers: auth_headers(sign_in_token(@global_read_admin)),
        as: :json

    assert_response :ok, response.body
    assert_equal @assignment.id, response.parsed_body.dig('essay_assignment', 'id')

    get "/api/v1/essay_assignments/#{@assignment.id}/statistics",
        headers: auth_headers(sign_in_token(@global_read_admin)),
        as: :json

    assert_response :ok, response.body
    assert_equal true, response.parsed_body['success']

    post "/api/v1/essay_assignments/#{@assignment.id}/send_reminders",
         headers: auth_headers(sign_in_token(@global_read_admin)),
         as: :json
    assert_response :unprocessable_entity, response.body
    assert_equal 'No students to remind', response.parsed_body['error']
  end

  test 'global read admin can inspect a student grading without a share' do
    get "/api/v1/essay_gradings/#{@grading.id}.json",
        headers: auth_headers(sign_in_token(@global_read_admin)),
        as: :json

    assert_response :ok, response.body
    assert_equal @grading.id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal @assignment.id,
                 response.parsed_body.dig('essay_grading', 'essay_assignment', 'id')
  end

  test 'global admin can edit release distribute share and update a grading' do
    token = sign_in_token(@global_read_admin)

    put "/api/v1/essay_assignments/#{@assignment.id}.json",
        params: { essay_assignment: { title: 'Updated by global admin' } },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_equal 'Updated by global admin', @assignment.reload.title

    patch "/api/v1/essay_assignments/#{@assignment.id}/release_scores.json",
          headers: auth_headers(token),
          as: :json
    assert_response :ok, response.body
    assert @assignment.reload.scores_released?
    assert_equal @global_read_admin.id.to_s, @assignment.meta['score_released_by_id'].to_s

    get '/api/v1/essay_assignments/distribution_options',
        params: { school_academic_year_id: @academic_year.id },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_includes response.parsed_body.dig('options', 'students').pluck('id'), @student.id

    get '/api/v1/essay_assignments/share_options',
        params: { essay_assignment_id: @assignment.id },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_includes response.parsed_body.fetch('teachers').pluck('id'), @share_recipient.id

    post "/api/v1/essay_assignments/#{@assignment.id}/distributions/add_students",
         params: { student_ids: [@student.id], deadline: 1.week.from_now.iso8601 },
         headers: auth_headers(token),
         as: :json
    assert_response :ok, response.body
    assert @assignment.assignment_student_assignments.exists?(general_user_id: @student.id)

    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [@share_recipient.id] },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert @assignment.shared_with?(@share_recipient)

    put "/api/v1/essay_gradings/#{@grading.id}.json",
        params: { essay_grading: { essay: 'Updated by global admin' } },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_equal 'Updated by global admin', @grading.reload.essay

    patch "/api/v1/essay_gradings/#{@grading.id}/teacher_review",
          params: {
            teacher_review: {
              score: { data: { 'Overall Score' => 18, 'Full Score' => 20 } }
            }
          },
          headers: auth_headers(token),
          as: :json
    assert_response :ok, response.body
    assert_equal true, @grading.reload.teacher_review_hash['confirmed']
  end

  test 'global admin can delete an assignment owned by another teacher' do
    delete "/api/v1/essay_assignments/#{@assignment.id}.json",
           headers: auth_headers(sign_in_token(@global_read_admin)),
           as: :json
    assert_response :ok, response.body
    assert_not EssayAssignment.exists?(@assignment.id)
  end

  test 'shared teacher keeps existing assignment and grading access' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @global_read_admin,
      teacher_ids: [@share_recipient.id]
    )
    token = sign_in_token(@share_recipient)

    get "/api/v1/essay_assignments/#{@assignment.id}.json",
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_equal 'shared', response.parsed_body.dig('essay_assignment', 'access_type')

    get "/api/v1/essay_gradings/#{@grading.id}.json",
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body

    put "/api/v1/essay_gradings/#{@grading.id}.json",
        params: { essay_grading: { essay: 'Updated by shared teacher' } },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_equal 'Updated by shared teacher', @grading.reload.essay
  end

  test 'global admin uses a legacy assignment distribution as its school context' do
    distribution = AssignmentDistribution.create!(
      essay_assignment: @assignment,
      school: @school,
      school_academic_year: @academic_year,
      distribution_type: 'individual',
      target_student_id: @student.id,
      deadline: 1.week.from_now,
      status: :active
    )
    @assignment.update_column(:school_academic_year_id, nil)
    token = sign_in_token(@global_read_admin)

    get '/api/v1/essay_assignments/distribution_options',
        params: { essay_assignment_id: @assignment.id },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    assert_equal @academic_year.id.to_s,
                 response.parsed_body.dig('options', 'school_academic_year', 'id').to_s
    assert_includes response.parsed_body.dig('options', 'students').pluck('id'), @student.id

    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [@share_recipient.id] },
        headers: auth_headers(token),
        as: :json
    assert_response :ok, response.body
    share = @assignment.active_essay_assignment_shares.find_by!(shared_with_general_user: @share_recipient)
    assert_equal distribution.school_id, share.school_id
    assert_equal distribution.school_academic_year_id, share.school_academic_year_id
  end

  test 'global admin never falls back to the admin account school for an unscoped legacy assignment' do
    admin_school = School.create!(
      name: "Admin Account School #{SecureRandom.hex(4)}",
      code: "admin-account-school-#{SecureRandom.hex(4)}",
      timezone: 'Asia/Hong_Kong',
      meta: {}
    )
    admin_year = SchoolAcademicYear.create!(
      school: admin_school,
      name: '2026-2027',
      start_date: Date.new(2026, 8, 1),
      end_date: Date.new(2027, 7, 31),
      status: :active,
      meta: {}
    )
    wrong_school_teacher = create_user!('wrong-school-teacher', 'wrong-school-teacher@example.test')
    [@global_read_admin, wrong_school_teacher].each do |teacher|
      TeacherAssignment.create!(
        general_user: teacher,
        school_academic_year: admin_year,
        department: 'English',
        position: 'Teacher',
        status: :active,
        meta: {}
      )
    end
    @assignment.update_column(:school_academic_year_id, nil)
    token = sign_in_token(@global_read_admin)

    get '/api/v1/essay_assignments/distribution_options',
        params: { essay_assignment_id: @assignment.id },
        headers: auth_headers(token),
        as: :json
    assert_response :not_found, response.body
    assert_equal 'Assignment school context not found', response.parsed_body['error']

    post "/api/v1/essay_assignments/#{@assignment.id}/distributions/add_students",
         params: { student_ids: [@student.id], deadline: 1.week.from_now.iso8601 },
         headers: auth_headers(token),
         as: :json
    assert_response :not_found, response.body
    assert_empty @assignment.assignment_distributions

    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [wrong_school_teacher.id] },
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden, response.body
    assert_empty @assignment.active_essay_assignment_shares
  end

  test 'an unrelated teacher still cannot inspect another teachers records by id' do
    token = sign_in_token(@unrelated_teacher)

    get "/api/v1/essay_assignments/#{@assignment.id}.json",
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden

    get "/api/v1/essay_assignments/#{@assignment.id}/statistics",
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden

    get "/api/v1/essay_gradings/#{@grading.id}.json",
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden

    put "/api/v1/essay_assignments/#{@assignment.id}.json",
        params: { essay_assignment: { title: 'Unauthorized title' } },
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden

    patch "/api/v1/essay_assignments/#{@assignment.id}/release_scores.json",
          headers: auth_headers(token),
          as: :json
    assert_response :forbidden

    put "/api/v1/essay_gradings/#{@grading.id}.json",
        params: { essay_grading: { essay: 'Unauthorized grading change' } },
        headers: auth_headers(token),
        as: :json
    assert_response :forbidden
  end

  test 'existing owner and student access remains available' do
    get "/api/v1/essay_assignments/#{@assignment.id}.json",
        headers: auth_headers(sign_in_token(@owner)),
        as: :json
    assert_response :ok, response.body

    get "/api/v1/essay_gradings/#{@grading.id}.json",
        headers: auth_headers(sign_in_token(@owner)),
        as: :json
    assert_response :ok, response.body

    put "/api/v1/essay_gradings/#{@grading.id}.json",
        params: { essay_grading: { essay: 'Reviewed by assignment owner' } },
        headers: auth_headers(sign_in_token(@owner)),
        as: :json
    assert_response :ok, response.body
    assert_equal 'Reviewed by assignment owner', @grading.reload.essay

    get "/api/v1/essay_gradings/#{@grading.id}.json",
        headers: auth_headers(sign_in_token(@student)),
        as: :json
    assert_response :ok, response.body
  end

  private

  def create_user!(nickname, email, role: 'teacher')
    GeneralUser.create!(
      email:,
      password: 'Password123!',
      nickname:,
      meta: {
        'aienglish_role' => role,
        'aienglish_features_list' => GeneralUser::VALID_AI_ENGLISH_FEATURES
      },
      konnecai_tokens: {}
    )
  end

  def sign_in_token(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    "Bearer #{token}"
  end

  def auth_headers(token)
    { 'Authorization' => token }
  end
end
