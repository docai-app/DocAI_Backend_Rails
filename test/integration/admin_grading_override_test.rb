# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AdminGradingOverrideTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @previous_token = ENV['ADMIN_TOKEN']
    ENV['ADMIN_TOKEN'] = 'isolated-admin-server-token-with-32-characters'
    @admin_headers = { 'Authorization' => "Bearer #{ENV['ADMIN_TOKEN']}" }
    @user = GeneralUser.create!(email: "override-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Practice', title: 'Practice', assignment: 'Practice', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Practice', essay: 'I am happy.', status: :draft, grading: {}, general_context: {}, revised_essay: {}, meta: {})
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    @questions = { 'quizTitle' => 'Practice', 'sections' => [{ 'topic' => 'Verbs', 'type' => 'multiple_choice', 'questions' => [{ 'question' => 'I __ happy.', 'options' => ['am', 'is'], 'answer' => 'am' }] }] }
    EssayGenerationJob.clear
    EssayGenerationNotificationJob.clear
  end

  teardown { ENV['ADMIN_TOKEN'] = @previous_token }

  EssayGrading.statuses.keys.each do |status|
    test "Admin bulk rerun accepts submission status #{status} and missing generation history" do
      @grading.update_columns(status: EssayGrading.statuses.fetch(status))
      post '/api/admin/v1/essay_gradings/bulk_rerun_workflow', params: { ids: [@grading.id] }, headers: @admin_headers, as: :json
      assert_response :ok, response.body
      assert_equal 1, response.parsed_body.dig('summary', 'succeeded')
      assert_equal 'pending', @grading.reload.status
      assert_equal 1, EssayGenerationJob.jobs.size
      run = EssayGenerationRun.find_by!(essay_grading: @grading, kind: 'grading')
      assert_equal 'queued', run.state
      assert_equal 0, run.attempts
    end
  end

  test 'ordinary requests remain unable to override unknown and student cannot use Admin endpoint' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    run.update_columns(state: 'unknown')
    old_token = run.token
    assert_raises(EssayGenerationRun::Unavailable) { @grading.rerun_workflow }
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    post "/api/admin/v1/essay_gradings/#{@grading.id}/rerun_workflow", headers: { 'Authorization' => "Bearer #{token}" }, params: { admin_override: true }, as: :json
    assert_response :unauthorized
    assert_equal old_token, run.reload.token
    assert_equal 'unknown', run.state
  end

  test 'old running task cannot persist results errors provider observations or completion' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    old_token = run.token
    assert run.claim!(old_token)
    service = EssayGradingService.new(@user.id, @grading, generation: run, token: old_token)
    run.begin_provider!(old_token, 'grading', provider: 'workflow', app_key: 'test')
    replacement = EssayGenerationRun.request_admin_rerun!(@grading)
    assert_not_equal old_token, replacement.token
    assert_raises(EssayGenerationRun::StaleExecution) { run.persist_stage!(old_token, 'grading') { flunk 'old content write' } }
    assert_raises(EssayGenerationRun::StaleExecution) { service.send(:record_workflow_error, 'grading', 'late failure') }
    assert_raises(EssayGenerationRun::StaleExecution) { run.with_execution!(old_token) { flunk 'late summary write' } }
    assert_raises(EssayGenerationRun::StaleExecution) { run.observe_provider!(old_token, { 'event' => 'workflow_finished', 'data' => { 'status' => 'succeeded' } }) }
    run.finish!(old_token, success: true)
    run.finish!(old_token, success: false)
    run.finish!(old_token, success: false, unknown: true)
    assert_equal 'queued', run.reload.state
    assert_equal 'pending', @grading.reload.status
    assert_nil @grading.meta['last_grading_error']
    assert_empty EssayGenerationNotificationJob.jobs
    assert run.claim!(replacement.token)
  end

  test 'override resets exhausted budgets checkpoints and attention but records bounded audit history' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    provider_id = SecureRandom.uuid
    run.update_columns(state: 'unknown', attempts: 3, completed_stages: ['grading'], recovery_count: 2,
      provider_context: { 'run_id' => provider_id }, attention_required_at: Time.current, resume_pending: true)
    @grading.update_columns(meta: { 'keep' => true, 'admin_reruns' => 25.times.map { |i| { 'at' => i } } })
    replacement = EssayGenerationRun.request_admin_rerun!(@grading)
    assert_equal 0, replacement.attempts
    assert_equal 0, replacement.recovery_count
    assert_empty replacement.completed_stages
    assert_empty replacement.provider_context
    assert_nil replacement.attention_required_at
    assert_not replacement.resume_pending
    audit = @grading.reload.meta['admin_reruns']
    assert_equal 20, audit.size
    assert_equal provider_id, audit.last['previous_run_id']
    assert_equal 'unknown', audit.last['previous_state']
    assert @grading.meta['keep']
  end

  test 'active supplement is fenced and requeued only after replacement main succeeds' do
    supplement = EssayGenerationRun.request!(@grading, kind: 'supplement')
    old_token = supplement.token
    assert supplement.claim!(old_token)
    EssayGenerationJob.clear
    main = EssayGenerationRun.request_admin_rerun!(@grading)
    assert_equal 'cancelled', supplement.reload.state
    assert_not_equal old_token, supplement.token
    assert_raises(EssayGenerationRun::StaleExecution) { supplement.persist_stage!(old_token, 'supplement') { flunk 'obsolete questions write' } }
    supplement.finish!(old_token, success: true)
    assert_equal 'cancelled', supplement.reload.state
    assert_equal 1, EssayGenerationJob.jobs.size
    assert main.claim!(main.token)
    main.finish!(main.token, success: true)
    assert_equal 'queued', supplement.reload.state
    assert_equal 2, EssayGenerationJob.jobs.size
    assert_equal 'graded', @grading.reload.status
  end

  test 'valid exercise and saved student answers survive override of an active supplement' do
    supplement = EssayGenerationRun.request!(@grading, kind: 'supplement')
    @grading.update_columns(grading: { 'supplement_practice' => { 'text' => @questions.to_json } })
    supplement.update_columns(state: 'ready')
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    post "/api/v1/essay_gradings/#{@grading.id}/supplement_practice/draft", params: { answers: { sections: [] }, using_time: 12 }, headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    assert_response :ok, response.body
    saved = @grading.supplement_practice_records.first!.attributes
    supplement.update_columns(state: 'unknown')
    EssayGenerationJob.clear
    main = EssayGenerationRun.request_admin_rerun!(@grading)
    assert_equal 'ready', supplement.reload.state
    assert main.claim!(main.token)
    main.finish!(main.token, success: true)
    assert_equal saved, @grading.supplement_practice_records.first!.reload.attributes
    assert_equal @questions.to_json, @grading.reload.grading.dig('supplement_practice', 'text')
    assert_equal 1, EssayGenerationJob.jobs.size
  end

  test 'bulk missing ID reports failure without losing valid requests' do
    post '/api/admin/v1/essay_gradings/bulk_rerun_workflow', params: { ids: [SecureRandom.uuid, @grading.id] }, headers: @admin_headers, as: :json
    assert_response :ok
    assert_equal 1, response.parsed_body.dig('summary', 'succeeded')
    assert_equal 1, response.parsed_body.dig('summary', 'failed')
    assert_equal 1, EssayGenerationJob.jobs.size
  end

  test 'late exception cannot attach its failure summary to replacement grading' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    old_token = run.token
    assert run.claim!(old_token)
    service = EssayGradingService.new(@user.id, @grading, generation: run, token: old_token)
    replace = ->(*) { EssayGenerationRun.request_admin_rerun!(EssayGrading.find(@grading.id)) }
    service.stub(:execute_workflow_streaming, ->(*) { raise 'old provider failure' }) do
      service.stub(:record_workflow_error, replace) do
        assert_raises(EssayGenerationRun::StaleExecution) { service.run_workflows }
      end
    end
    assert_nil @grading.reload.meta['grading_failure']
    assert_equal 'queued', run.reload.state
  end

  test 'old worker does not send completion notification for a newer ready attempt' do
    @assignment.update_columns(category: 'sentence_builder')
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    old_token = run.token
    service = Object.new
    record_id = @grading.id
    service.define_singleton_method(:run_workflows) do
      replacement = EssayGenerationRun.request_admin_rerun!(EssayGrading.find(record_id))
      replacement.claim!(replacement.token)
      replacement.finish!(replacement.token, success: true)
      true
    end
    worker = EssayGenerationJob.new
    EssayGradingService.stub(:new, service) do
      worker.stub(:notify_completion, ->(*) { flunk 'obsolete worker notification' }) do
        worker.perform(run.id, old_token)
      end
    end
    assert_equal 'ready', run.reload.state
    assert_not_equal old_token, run.token
  end
end
