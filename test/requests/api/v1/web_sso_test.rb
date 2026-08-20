# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class ApiV1WebSsoTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  PASSWORD = 'Password123!'
  TEST_TICKET = 'A' * 48

  class FakeTicketStore
    attr_accessor :payload

    def issue(payload)
      self.payload = payload.stringify_keys
      TEST_TICKET
    end

    def consume(ticket)
      raise WebSso::TicketStore::InvalidTicketError unless ticket == TEST_TICKET && payload

      value = payload
      self.payload = nil
      value
    end
  end

  class AllowAllRateLimiter
    def check!(scope:, identifier:)
      scope.present? && identifier.present?
    end
  end

  setup do
    host! 'docai.m2mda.com'
    @user = create_user('student')
    @other_user = create_user('student')
    @assignment = EssayAssignment.create!(
      general_user: @user,
      assignment: 'Web SSO Test',
      topic: 'Result handoff',
      title: 'Student result handoff',
      code: SecureRandom.hex(4),
      category: :essay,
      rubric: { 'criteria' => 'Test' },
      meta: {}
    )
    @grading = create_grading(@user, status: :graded)
    @other_grading = create_grading(@other_user, status: :graded)
    @ticket_store = FakeTicketStore.new
    @rate_limiter = AllowAllRateLimiter.new
  end

  test 'requires a General User JWT to create a ticket' do
    post tickets_path, params: { essay_grading_id: @grading.id }, as: :json

    assert_response :unauthorized
  end

  test 'does not reveal or create tickets for another student result' do
    with_sso_stubs do
      post tickets_path,
           params: { essay_grading_id: @other_grading.id },
           headers: { 'Authorization' => sign_in_token },
           as: :json
    end

    assert_response :not_found
    assert_nil @ticket_store.payload
  end

  test 'does not create a result ticket for a draft' do
    draft = create_grading(@user, status: :draft)

    with_sso_stubs do
      post tickets_path,
           params: { essay_grading_id: draft.id },
           headers: { 'Authorization' => sign_in_token },
           as: :json
    end

    assert_response :conflict
    assert_equal 'RESULT_NOT_AVAILABLE', JSON.parse(response.body)['error_code']
  end

  test 'creates and exchanges a one-time ticket for the same student result' do
    with_sso_stubs do
      post tickets_path,
           params: { essay_grading_id: @grading.id },
           headers: { 'Authorization' => sign_in_token },
           as: :json

      assert_response :created
      create_body = JSON.parse(response.body)
      assert_equal true, create_body['success']
      assert_equal 60, create_body['expires_in']
      assert_equal "https://aienglish.docai.net/miniprogram/sso#ticket=#{TEST_TICKET}", create_body['web_url']
      assert_not_includes create_body['web_url'], '?ticket='

      post exchange_path, params: { ticket: TEST_TICKET }, as: :json

      assert_response :success
      exchange_body = JSON.parse(response.body)
      assert_equal true, exchange_body['success']
      assert_equal "/essay/grading/#{@grading.id}", exchange_body['redirect_path']
      assert_equal @user.email, exchange_body.dig('user', 'email')
      assert response.headers['Authorization'].present?, 'exchange must dispatch the normal General User JWT'

      post exchange_path, params: { ticket: TEST_TICKET }, as: :json
      assert_response :unauthorized
      assert_equal 'WEB_SSO_TICKET_INVALID', JSON.parse(response.body)['error_code']
    end
  end

  test 'rejects non-student accounts' do
    teacher = create_user('teacher')
    teacher_grading = create_grading(teacher, status: :graded)

    with_sso_stubs do
      post tickets_path,
           params: { essay_grading_id: teacher_grading.id },
           headers: { 'Authorization' => sign_in_token(teacher) },
           as: :json
    end

    assert_response :forbidden
    assert_equal 'STUDENT_ACCOUNT_REQUIRED', JSON.parse(response.body)['error_code']
  end

  private

  def tickets_path
    '/api/v1/general_users/web_sso/tickets'
  end

  def exchange_path
    '/api/v1/general_users/web_sso/exchange'
  end

  def create_user(role)
    GeneralUser.create!(
      email: "web-sso-#{role}-#{SecureRandom.hex(5)}@example.test",
      password: PASSWORD,
      nickname: "Web SSO #{role.titleize}",
      meta: {
        'aienglish_role' => role,
        'aienglish_features_list' => ['essay']
      },
      konnecai_tokens: {}
    )
  end

  def create_grading(user, status:)
    grading = EssayGrading.create!(
      general_user: user,
      essay_assignment: @assignment,
      status: :draft,
      grading: {},
      general_context: {},
      meta: {}
    )
    grading.update_column(:status, EssayGrading.statuses.fetch(status.to_s)) unless status == :draft
    grading.reload
  end

  def sign_in_token(user = @user)
    post '/general_users/sign_in',
         params: { general_user: { email: user.email, password: PASSWORD } },
         as: :json
    response.headers['Authorization'].to_s.tap { |token| assert token.present? }
  end

  def with_sso_stubs(&block)
    WebSso::TicketStore.stub(:new, @ticket_store) do
      WebSso::RateLimiter.stub(:new, @rate_limiter, &block)
    end
  end
end
