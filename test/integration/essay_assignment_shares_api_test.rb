# frozen_string_literal: true

require 'test_helper'

class EssayAssignmentSharesApiTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @context = build_share_api_context
    @owner = @context[:owner]
    @recipient = @context[:recipient]
    @other_teacher = @context[:other_teacher]
    @assignment = @context[:assignment]
    @school = @context[:school]
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

  test 'only the owner can read sharing recipients even when another teacher knows the assignment id' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    [@recipient_token, sign_in_token(@other_teacher)].each do |token|
      get "/api/v1/essay_assignments/#{@assignment.id}/shares", headers: auth_headers(token), as: :json
      assert_response :forbidden
      assert_not JSON.parse(response.body).key?('shared_teachers')
    end
  end

  test 'malformed recipient lists and unknown emails never remove an existing share' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    invalid_payloads = [
      {}, { teacher_ids: nil }, { teacher_ids: '' }, { teacher_ids: [nil] },
      { teacher_ids: [' '] }, { teacher_ids: { bad: @recipient.id } },
      { teacher_emails: 'unknown@example.test' }, { teacher_emails: [' '] },
      { teacher_emails: ['unknown@example.test'] },
      { teacher_emails: [@other_teacher.email, 'unknown@example.test'] }
    ]
    invalid_payloads.each do |payload|
      put "/api/v1/essay_assignments/#{@assignment.id}/shares",
          params: payload, headers: auth_headers(@owner_token), as: :json
      assert_response :unprocessable_entity, "Unexpected success for #{payload.inspect}"
      assert_equal [@recipient.id], @assignment.essay_assignment_shares.active.pluck(:shared_with_general_user_id)
    end
  end

  test 'explicit empty recipient list removes shares and repeated identical saves are safe' do
    2.times do
      put "/api/v1/essay_assignments/#{@assignment.id}/shares",
          params: { teacher_ids: [@recipient.id] }, headers: auth_headers(@owner_token), as: :json
      assert_response :success
      assert_equal 1, @assignment.essay_assignment_shares.active.count
    end
    put "/api/v1/essay_assignments/#{@assignment.id}/shares",
        params: { teacher_ids: [] }, headers: auth_headers(@owner_token), as: :json
    assert_response :success
    assert_empty JSON.parse(response.body)['shared_teachers']
    assert_empty @assignment.essay_assignment_shares.active
  end

  test 'legacy email sharing supports case normalization and duplicate emails' do
    post "/api/v1/essay_assignments/#{@assignment.id}/share",
         params: { teacher_emails: [" #{@recipient.email.upcase} ", @recipient.email] },
         headers: auth_headers(@owner_token), as: :json
    assert_response :success
    assert_equal [@recipient.id], JSON.parse(response.body)['shared_teachers'].map { |item| item['id'] }
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
    assert_kind_of Array, body['essay_assignments'], body.inspect
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

  test 'teacher index filters owned and shared assignments by academic year dates' do
    current_owned = create_assignment!(
      user: @recipient,
      title: 'Current Year Assignment'
    )
    historical_year = SchoolAcademicYear.create!(
      school: @school,
      name: "#{Date.current.year - 1}-#{Date.current.year}",
      start_date: Date.current.prev_year.beginning_of_year,
      end_date: Date.current.prev_year.end_of_year,
      status: :archived,
      meta: {}
    )
    [@owner, @recipient].each do |teacher|
      TeacherAssignment.create!(
        general_user: teacher,
        school_academic_year: historical_year,
        department: 'English',
        position: 'Teacher',
        status: :active,
        meta: {}
      )
    end

    historical_owned = create_assignment!(
      user: @recipient,
      title: 'Historical Owned Assignment'
    )
    historical_shared = create_assignment!(
      user: @owner,
      title: 'Historical Shared Assignment'
    )
    historical_at = Time.zone.local(Date.current.year - 1, 6, 15, 12)
    [historical_owned, historical_shared].each do |assignment|
      assignment.update_columns(created_at: historical_at, updated_at: historical_at)
    end

    EssayAssignmentShareService.sync_shares!(
      assignment: historical_shared,
      actor: @owner,
      teacher_ids: [@recipient.id]
    )

    get '/api/v1/essay_assignments',
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :success
    current_body = JSON.parse(response.body)
    assert_kind_of Array, current_body['essay_assignments'], current_body.inspect
    current_ids = current_body['essay_assignments'].map { |item| item['id'] }
    assert_includes current_ids, current_owned.id
    assert_not_includes current_ids, historical_owned.id
    assert_not_includes current_ids, historical_shared.id

    get '/api/v1/essay_assignments',
        params: { school_academic_year_id: historical_year.id },
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :success
    historical_body = JSON.parse(response.body)
    historical_ids = historical_body['essay_assignments'].map { |item| item['id'] }
    assert_includes historical_ids, historical_owned.id
    assert_includes historical_ids, historical_shared.id
    assert_not_includes historical_ids, current_owned.id
    assert_equal 2, historical_body.dig('meta', 'total_count')

    get '/api/v1/essay_assignments',
        params: {
          general_user_id: @owner.id,
          school_academic_year_id: historical_year.id
        },
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :success
    owner_historical_ids = JSON.parse(response.body)['essay_assignments'].map { |item| item['id'] }
    assert_equal [historical_shared.id], owner_historical_ids
  end

  test 'teacher index rejects an academic year outside the teacher account' do
    other_school = School.create!(
      name: "Unavailable Year School #{SecureRandom.hex(4)}",
      code: "unavailable-year-#{SecureRandom.hex(4)}",
      meta: {}
    )
    unavailable_year = SchoolAcademicYear.create!(
      school: other_school,
      name: 'Unavailable Year',
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: :active,
      meta: {}
    )

    get '/api/v1/essay_assignments',
        params: { school_academic_year_id: unavailable_year.id },
        headers: auth_headers(@recipient_token),
        as: :json

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'The selected academic year is not available for this account.', body['error']
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

  test 'revoked share cannot read assignment details' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    @assignment.essay_assignment_shares.find_by!(shared_with_general_user: @recipient).revoke!

    get "/api/v1/essay_assignments/#{@assignment.id}/read",
        headers: auth_headers(@recipient_token), as: :json

    assert_response :forbidden
  end

  test 'shared recipient without category permission cannot use the student read exception' do
    EssayAssignmentShareService.sync_shares!(assignment: @assignment, actor: @owner, teacher_ids: [@recipient.id])
    @recipient.update!(meta: @recipient.meta.merge('aienglish_features_list' => []))

    get "/api/v1/essay_assignments/#{@assignment.id}/read",
        headers: auth_headers(@recipient_token), as: :json

    assert_response :forbidden
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

  test 'eight eligible current teachers produce seven unique candidates excluding the viewer' do
    added = 5.times.map do |index|
      create_teacher!(year: @context[:year], nickname: "Current Teacher #{index}", features: %w[essay])
    end
    locked = create_teacher!(year: @context[:year], nickname: 'Locked Teacher', features: %w[essay])
    locked.update!(locked_at: Time.current)

    get '/api/v1/essay_assignments/share_options', headers: auth_headers(@owner_token), as: :json
    assert_response :success
    body = JSON.parse(response.body)
    expected = [@recipient.id, @other_teacher.id, *added.map(&:id)].sort
    assert_equal 7, body['teachers'].length
    assert_equal expected, body['teachers'].map { |teacher| teacher['id'] }.sort
    assert_equal body['teachers'], body.dig('options', 'teachers')
  end

  test 'share_options excludes locked and archived year teachers in both response formats' do
    @recipient.update!(locked_at: Time.current)
    @recipient.teacher_assignments.first.update!(department: 'Locked Department')
    old_year = SchoolAcademicYear.create!(
      school: @school, name: '2023', start_date: Date.new(2023, 1, 1),
      end_date: Date.new(2023, 12, 31), status: :archived, meta: {}
    )
    legacy = create_teacher!(year: old_year, nickname: 'Legacy Teacher', features: %w[essay])
    legacy.update!(school_id: @school.id)

    get '/api/v1/essay_assignments/share_options', headers: auth_headers(@owner_token), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [@other_teacher.id], body['teachers'].map { |teacher| teacher['id'] }
    assert_equal body['teachers'], body.dig('options', 'teachers')
    assert_equal ['English'], body.dig('options', 'departments')
  end

  test 'sync cannot bypass candidate filtering using a locked teacher id or email' do
    @recipient.update!(locked_at: Time.current)
    [{ teacher_ids: [@recipient.id] }, { teacher_emails: [@recipient.email] }].each do |params|
      put "/api/v1/essay_assignments/#{@assignment.id}/shares",
          params: params, headers: auth_headers(@owner_token), as: :json
      assert_response :unprocessable_entity
      assert JSON.parse(response.body)['details'].any? { |item| item['error'] == 'teacher_locked' }
      assert_empty @assignment.essay_assignment_shares
    end
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

    owner = create_teacher!(year: year, nickname: 'Owner Teacher', features: %w[essay])
    recipient = create_teacher!(year: year, nickname: 'Recipient Teacher', features: %w[essay])
    other_teacher = create_teacher!(year: year, nickname: 'Other Teacher', features: %w[essay])

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

  def sign_in_token(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    "Bearer #{token}"
  end

  def auth_headers(token)
    { 'Authorization' => token }
  end
end
