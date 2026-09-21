require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AdminSupplementMonitorTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  setup do
    host! 'localhost'
    @previous_token = ENV['ADMIN_TOKEN']
    ENV['ADMIN_TOKEN'] = 'isolated-supplement-monitor-token'
    @headers = { 'Authorization' => "Bearer #{ENV['ADMIN_TOKEN']}" }
    @user = GeneralUser.create!(email: "supp-monitor-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    school = School.create!(name: 'Test school', code: SecureRandom.hex(8))
    @year = SchoolAcademicYear.create!(school: school, name: 'Current', start_date: Date.current - 30, end_date: Date.current + 300, status: :active)
    @old_year = SchoolAcademicYear.create!(school: school, name: 'Old active', start_date: Date.current - 400, end_date: Date.current - 35, status: :active)
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Test', title: 'Test', assignment: 'Essay', category: :essay, rubric: { 'name' => 'Test' }, meta: {}, school_academic_year_id: @year.id)
  end
  teardown { ENV['ADMIN_TOKEN'] = @previous_token }

  def make_grading(state = 'failed', age: 3.hours, status: :graded, year: @year)
    g = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Test', essay: 'PRIVATE ESSAY', status: :draft, grading: { 'score' => 80 }, meta: {})
    g.update_columns(status: EssayGrading.statuses[:graded], submission_academic_year_id: year&.id)
    run = EssayGenerationRun.request!(g, kind: 'supplement')
    run.update_columns(state: state, queued_at: Time.current - age, started_at: Time.current - age, finished_at: state == 'failed' ? 2.minutes.ago : nil, failure_code: state == 'failed' ? 'invalid_output' : nil, provider_context: { 'key_digest' => 'PRIVATE KEY', 'terminal' => 'PRIVATE OUTPUT' })
    g.update_columns(status: EssayGrading.statuses.fetch(status.to_s))
    [g, run]
  end

  def list(status = nil, include_supplement: true)
    get '/api/admin/v1/essay_gradings/pending_or_stopped', headers: @headers, params: { include_supplement: include_supplement.to_s, status: status }
    assert_response :ok, response.body
    response.parsed_body
  end

  test 'adds graded supplement issues exactly once with accurate filters and counts' do
    failed, = make_grading
    unknown, = make_grading('unknown', age: 1.minute)
    stale, = make_grading('queued')
    pending, = make_grading(status: :pending)
    stopped, = make_grading(status: :stopped)
    make_grading('ready')
    make_grading('cancelled')
    make_grading('running', age: 10.minutes)
    make_grading('queued', age: 10.minutes)
    make_grading(year: @old_year)
    body = list
    assert_equal [failed.id, unknown.id, stale.id, pending.id, stopped.id].sort, body['essay_gradings'].map { |g| g['id'] }.sort
    assert_equal 5, body.dig('meta', 'total')
    assert_equal 3, body.dig('meta', 'supplement')
    assert_equal 1, body.dig('meta', 'pending')
    assert_equal 1, body.dig('meta', 'stopped')
    assert_equal true, body.dig('meta', 'supplement_monitor')
    row = body['essay_gradings'].find { |g| g['id'] == failed.id }
    assert_equal 'graded', row['status']
    assert_equal 'supplement', row['issue_kind']
    assert_equal true, row.dig('supplement_generation', 'can_retry')
    assert_equal 'supplement', row.dig('supplement_generation', 'failure_stage')
    %w[PRIVATE].each { |secret| refute_includes response.body, secret }
    assert_equal [failed.id, unknown.id, stale.id].sort, list('supplement')['essay_gradings'].map { |g| g['id'] }.sort
    assert_equal [pending.id], list('pending')['essay_gradings'].map { |g| g['id'] }
    assert_equal [stopped.id], list('stopped')['essay_gradings'].map { |g| g['id'] }
    assert_equal [pending.id, stopped.id].sort, list(nil, include_supplement: false)['essay_gradings'].map { |g| g['id'] }.sort
  end

  test 'waiting clocks exclude future retry and newly started jobs and honor submission year' do
    g, run = make_grading('retry_wait')
    run.update_columns(next_retry_at: 1.hour.from_now)
    make_grading(year: @old_year)
    fallback, = make_grading(year: nil)
    started, run = make_grading('running')
    run.update_columns(started_at: 1.minute.ago)
    assert_equal [fallback.id], list('supplement')['essay_gradings'].map { |r| r['id'] }
  end

  test 'recovered supplement disappears without changing main grading' do
    g, run = make_grading
    assert_equal [g.id], list('supplement')['essay_gradings'].map { |r| r['id'] }
    run.update_columns(state: 'ready')
    assert_empty list('supplement')['essay_gradings']
    assert_equal 'graded', g.reload.status
    assert_equal 80, g.grading['score']
  end

  test 'safe retry only queues supplement once and preserves main grade' do
    g, run = make_grading
    post "/api/admin/v1/essay_gradings/#{g.id}/rerun_supplement_practice_workflow", headers: @headers, params: { retry_failed_only: true }, as: :json
    assert_response :ok, response.body
    assert_equal 'queued', run.reload.state
    token = run.token
    assert_equal 'graded', g.reload.status
    assert_equal 80, g.grading['score']
    post "/api/admin/v1/essay_gradings/#{g.id}/rerun_supplement_practice_workflow", headers: @headers, params: { retry_failed_only: true }, as: :json
    assert_response :conflict
    assert_equal token, run.reload.token
  end

  test 'safe retry refuses unknown ready and active runs without changing token' do
    %w[unknown ready running checking queued].each do |state|
      g, run = make_grading(state, age: 1.minute)
      token = run.token
      post "/api/admin/v1/essay_gradings/#{g.id}/rerun_supplement_practice_workflow", headers: @headers, params: { retry_failed_only: true }, as: :json
      assert_response :conflict, state
      assert_equal token, run.reload.token
    end
  end

  test 'safe retry protects existing student answers' do
    g, run = make_grading
    record = SupplementPracticeRecord.create!(essay_grading: g, essay_assignment: @assignment, general_user: @user, status: :draft, answers: { 'sections' => [] }, questions_data: {}, meta: {})
    before = record.attributes
    token = run.token
    post "/api/admin/v1/essay_gradings/#{g.id}/rerun_supplement_practice_workflow", headers: @headers, params: { retry_failed_only: true }, as: :json
    assert_response :conflict
    assert_equal token, run.reload.token
    assert_equal before, record.reload.attributes
    row = list('supplement')['essay_gradings'].find { |r| r['id'] == g.id }
    assert_equal false, row.dig('supplement_generation', 'can_retry')
  end

  test 'monitor and retry require admin authentication' do
    g, = make_grading
    get '/api/admin/v1/essay_gradings/pending_or_stopped', params: { include_supplement: true }
    assert_response :unauthorized
    post "/api/admin/v1/essay_gradings/#{g.id}/rerun_supplement_practice_workflow", params: { retry_failed_only: true }, as: :json
    assert_response :unauthorized
  end
end
