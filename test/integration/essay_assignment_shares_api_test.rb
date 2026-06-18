# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentSharesApiTest < ActionDispatch::IntegrationTest
  setup do
    @context = build_share_api_context
    @owner = @context[:owner]
    @recipient = @context[:recipient]
    @other_teacher = @context[:other_teacher]
    @assignment = @context[:assignment]
    @owner_token = sign_in_token(@owner)
    @recipient_token = sign_in_token(@recipient)
  end

  test 'owner can sync shares and list shared teachers' do
    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [@recipient.id] },
        headers: auth_headers(@owner_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 1, body['shared_teachers'].size
    assert_equal @recipient.id.to_s, body['shared_teachers'].first['id'].to_s

    get "/api/v1/essay_assignments/#{@assignment.id}/shares",
        headers: auth_headers(@owner_token),
        as: :json

    assert_response :success
    list_body = JSON.parse(response.body)
    assert_equal 1, list_body['shared_teachers'].size
  end

  test 'recipient cannot sync shares' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [@other_teacher.id] },
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :forbidden
  end

  test 'teacher index merges owned and shared assignments' do
    owned = EssayAssignment.create!(
      general_user: @recipient,
      topic: 'Owned Topic',
      assignment: 'Owned Assignment',
      title: 'Owned Title',
      category: 'essay',
      rubric: default_rubric,
      meta: {}
    )

    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    get '/api/v1/essay_assignments',
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    ids = body['essay_assignments'].map { |item| item['id'] }
    assert_includes ids, owned.id
    assert_includes ids, @assignment.id

    shared_item = body['essay_assignments'].find { |item| item['id'] == @assignment.id }
    assert_equal 'shared', shared_item['access_type']
    assert_equal true, shared_item['shared_with_me']
    assert_equal 'Shared by Owner Teacher', shared_item['shared_by_label']
    assert_equal true, shared_item['can_assign_to_students']
    assert_equal @owner.id.to_s, shared_item.dig('owner', 'id').to_s
  end

  test 'shared recipient can read and update assignment' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    get "/api/v1/essay_assignments/#{@assignment.id}/read",
        headers: auth_headers(@recipient_token),
        as: :json
    assert_response :success

    put "/api/v1/essay_assignments/#{@assignment.id}",
        params: { essay_assignment: { title: 'Updated by recipient' } },
        headers: auth_headers(@recipient_token),
        as: :json
    assert_response :success
    assert_equal 'Updated by recipient', @assignment.reload.title
  end

  test 'shared recipient cannot delete assignment' do
    EssayAssignmentShareService.sync_shares!(
      assignment: @assignment,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    delete "/api/v1/essay_assignments/#{@assignment.id}",
           headers: auth_headers(@recipient_token),
           as: :json

    assert_response :forbidden
    assert EssayAssignment.exists?(@assignment.id)
  end

  test 'share_options returns same school teachers' do
    get '/api/v1/essay_assignments/share_options',
        headers: auth_headers(@owner_token),
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    teacher_ids = body.dig('options', 'teachers').map { |teacher| teacher['id'] }
    assert_includes teacher_ids, @recipient.id
    assert_not_includes teacher_ids, @owner.id
  end

  private

  def build_share_api_context
    school = School.create!(
      name: "Share API School #{SecureRandom.hex(4)}",
      code: "share-api-#{SecureRandom.hex(4)}",
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
      rubric: default_rubric,
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

  def sign_in_token(user)
    post '/general_users/sign_in',
         params: { general_user: { email: user.email, password: 'Password123!' } },
         as: :json
    response.headers['Authorization'].to_s
  end

  def auth_headers(token)
    { 'Authorization' => token }
  end
end
