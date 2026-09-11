# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class EssayGenerationRecoveryEdgesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    EssayGenerationJob.clear
    EssayGenerationNotificationJob.clear
    @user = GeneralUser.create!(email: "recovery-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: { 'aienglish_role' => 'student' }, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Practice', title: 'Practice', assignment: 'Practice', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Practice', essay: 'I am happy.', status: :draft, grading: {}, general_context: {}, revised_essay: {}, meta: {})
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @url = "/api/v1/essay_gradings/#{@grading.id}/supplement_practice"
  end

  test 'three failures with no content expose retry state and GET then POST recovers once' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    3.times do
      travel_to((run.reload.next_retry_at || Time.current) + 1.second) do
        token = run.token
        assert run.claim!(token)
        run.finish!(token, success: false)
      end
    end
    travel_to(run.reload.finished_at + 2.minutes) do
      assert_nil @grading.reload.grading['supplement_practice']
      get @url, headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal 'failed', response.parsed_body.dig('generation', 'state')
      assert_equal true, response.parsed_body.dig('generation', 'can_retry')
      assert_equal 'graded', @grading.reload.status
      EssayGenerationJob.clear
      post "#{@url}/retry", headers: @headers, as: :json
      assert_response :accepted
      assert_equal 'queued', response.parsed_body.dig('generation', 'state')
      post "#{@url}/retry", headers: @headers, as: :json
      assert_response :conflict
      assert_equal 1, EssayGenerationJob.jobs.length
      get @url, headers: @headers, as: :json
      assert_response :ok
      assert_equal 'queued', response.parsed_body.dig('generation', 'state')
      assert_equal false, response.parsed_body.dig('generation', 'can_retry')
    end
  end

  test 'failed empty output retains cooldown while absent legacy output remains unknown' do
    get @url, headers: @headers, as: :json
    assert_equal 'unknown', response.parsed_body.dig('generation', 'state')
    assert_equal false, response.parsed_body.dig('generation', 'can_retry')
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    run.update_columns(state: 'failed', finished_at: Time.current)
    @grading.update_columns(grading: { 'supplement_practice' => { 'text' => '' } })
    get @url, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 'failed', response.parsed_body.dig('generation', 'state')
    assert_equal false, response.parsed_body.dig('generation', 'can_retry')
    post "#{@url}/retry", headers: @headers, as: :json
    assert_response :conflict
  end

  [0, 1].each do |score|
    test "managed builder persists #{score}/1 while pending before publishing ready" do
      @assignment.update_columns(category: 'sentence_builder')
      feedback = { 'results' => [{ 'errors' => [{ 'error1' => score == 1 ? 'Correct' : 'Use am.' }] }] }
      @grading.update_columns(grading: { 'data' => { 'text' => "```json\n#{feedback.to_json}\n```" } })
      run = EssayGenerationRun.request!(@grading, kind: 'grading')
      assert run.claim!(run.token)
      service = EssayGradingService.new(@user.id, @grading.reload, generation: run, token: run.token)
      service.instance_variable_set(:@grading_success, true)
      assert service.send(:update_final_status)
      assert_equal 'pending', @grading.reload.status
      assert_equal score, @grading[:score]
      assert_equal 1, @grading.grading['full_score']
      assert_includes run.reload.completed_stages, 'summary'
      run.finish!(run.token, success: true)
      assert_equal 'graded', @grading.reload.status
      assert_equal 'ready', run.reload.state
      metrics = EssayGradingMetrics.call(@grading)
      assert_equal score, metrics[:score]
      assert_equal 1, metrics[:full_score]
    end
  end

  test 'invalid builder output cannot publish or mark the summary checkpoint complete' do
    @assignment.update_columns(category: 'sentence_builder')
    @grading.update_columns(grading: { 'data' => { 'text' => '{"results":[]}' } })
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    assert run.claim!(run.token)
    service = EssayGradingService.new(@user.id, @grading.reload, generation: run, token: run.token)
    service.instance_variable_set(:@grading_success, true)
    assert_raises(ArgumentError) { service.send(:update_final_status) }
    assert_equal 'pending', @grading.reload.status
    assert_nil @grading[:score]
    assert_not_includes run.reload.completed_stages, 'summary'
  end

  test 'actual builder worker saves scores before the completion webhook' do
    @assignment.update_columns(category: 'sentence_builder', meta: { 'vocabs' => [{ 'words' => 'happy' }] })
    @grading.update_columns(grading: { 'app_key' => 'test', 'sentence_builder' => [{ 'sentence' => 'I am happy.' }] })
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    service = EssayGradingService.new(@user.id, @grading.reload, generation: run, token: run.token)
    events = [{ 'event' => 'workflow_finished', 'data' => { 'status' => 'succeeded', 'outputs' => {
      'text' => { 'results' => [{ 'errors' => [] }] }.to_json
    } } }]
    worker = EssayGenerationJob.new
    notified = false
    notification = lambda do |record|
      notified = true
      assert_equal 'graded', record.status
      assert_equal 1, record[:score]
      assert_equal 1, record.grading['full_score']
      assert_nil record.grading['comprehension'], 'must not write through the unrelated score= accessor'
    end
    service.stub(:execute_workflow_streaming, [events, 'test']) do
      EssayGradingService.stub(:new, service) do
        worker.stub(:notify_completion, notification) { worker.perform(run.id, run.token) }
      end
    end
    assert notified
    assert_equal 'ready', run.reload.state
    assert_equal 1, run.attempts
    assert_empty EssayGenerationNotificationJob.jobs
  end

  %w[queued running checking retry_wait unknown].each do |state|
    test "admin single and bulk rerun report #{state} as not accepted without new jobs" do
      run = EssayGenerationRun.request!(@grading, kind: 'grading')
      run.update_columns(state: state)
      old_token = run.token
      EssayGenerationJob.clear
      post "/api/admin/v1/essay_gradings/#{@grading.id}/rerun_workflow", as: :json
      assert_response :conflict, response.body
      assert_equal false, response.parsed_body['success']
      result = Admin::EssayGradings::BulkRerunWorkflowService.new(ids: [@grading.id]).call
      assert_equal false, result.dig(:results, 0, :success)
      assert_equal 0, result.dig(:summary, :succeeded)
      assert_equal 1, result.dig(:summary, :failed)
      assert_empty EssayGenerationJob.jobs
      assert_equal old_token, run.reload.token
      assert_equal state, run.state
      # Callback/legacy duplicate delivery still has idempotent no-op behavior.
      assert_equal old_token, EssayGenerationRun.request!(@grading, kind: 'grading').token
    end
  end

  test 'admin supplement blocked and main confirmed failure accepted are truthful' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    run.update_columns(state: 'unknown')
    EssayGenerationJob.clear
    post "/api/admin/v1/essay_gradings/#{@grading.id}/rerun_supplement_practice_workflow", as: :json
    assert_response :conflict, response.body
    assert_equal false, response.parsed_body['success']
    assert_empty EssayGenerationJob.jobs
    run.update_columns(state: 'failed', finished_at: 2.minutes.ago)
    @grading.update_columns(status: EssayGrading.statuses[:stopped])
    post "/api/admin/v1/essay_gradings/#{@grading.id}/rerun_workflow", as: :json
    assert_response :ok, response.body
    assert_equal true, response.parsed_body['success']
    assert_equal 1, EssayGenerationJob.jobs.length
    assert_equal 'pending', @grading.reload.status
  end
end
