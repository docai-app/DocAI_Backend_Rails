# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class EssayGenerationReliabilityTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    EssayGenerationJob.clear
    EssayGenerationNotificationJob.clear
    @student = GeneralUser.create!(email: "generation-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: { 'aienglish_role' => 'student' }, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @student, topic: 'Practice', title: 'Practice', assignment: 'Practice', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @student, essay_assignment: @assignment, topic: 'Practice', essay: 'I am happy.', status: :draft, grading: {}, general_context: {}, revised_essay: {}, meta: {})
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    token, = Warden::JWTAuth::UserEncoder.new.call(@student, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @url = "/api/v1/essay_gradings/#{@grading.id}/supplement_practice"
    @questions = { 'quizTitle' => 'Practice', 'sections' => [{ 'topic' => 'Verbs', 'type' => 'multiple_choice', 'questions' => [{ 'question' => 'I __ happy.', 'options' => ['am', 'is'], 'answer' => 'am' }] }] }
  end

  test 'three confirmed failures stop and notify exactly once with no fourth attempt' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    3.times do |index|
      token = run.reload.token
      travel_to((run.next_retry_at || Time.current) + 1.second) do
        assert run.claim!(token)
        assert_not run.claim!(token), 'duplicate worker must not call provider'
        run.finish!(token, success: false)
      end
      assert_equal index + 1, run.reload.attempts
      assert_equal(index == 2 ? 'failed' : 'retry_wait', run.state)
      assert_equal(index == 2 ? 'stopped' : 'pending', @grading.reload.status)
    end
    assert_equal 3, EssayGenerationJob.jobs.length
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
    assert_equal run.id, EssayGenerationRun.request!(@grading, kind: 'grading').id
    assert_equal 3, run.reload.attempts
    delivery = Minitest::Mock.new
    delivery.expect(:deliver_now, true)
    AdminNotificationMailer.stub(:assignment_stopped_notification, delivery) do
      2.times { EssayGenerationNotificationJob.new.perform(run.id, run.token) }
    end
    delivery.verify
    assert run.reload.notified_at
  end

  test 'supplement failure never changes main score status or main feedback' do
    @grading.update_columns(score: 51, grading: { 'data' => { 'text' => 'keep' } })
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    3.times do
      travel_to((run.reload.next_retry_at || Time.current) + 1.second) do
        token = run.token
        assert run.claim!(token)
        run.finish!(token, success: false)
      end
    end
    assert_equal 'failed', run.reload.state
    assert_equal 'graded', @grading.reload.status
    assert_equal 51, @grading[:score]
    assert_equal 'keep', @grading.grading.dig('data', 'text')
  end

  test 'obsolete queued token cannot claim or overwrite and fresh request is deduplicated' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    old_token = run.token
    assert_not run.public_state[:can_retry]
    run.update_columns(queued_at: 3.hours.ago)
    assert run.public_state[:can_retry]
    replacement = EssayGenerationRun.request!(@grading, kind: 'supplement', manual: true, force: true)
    assert_not_equal old_token, replacement.token
    assert_not run.claim!(old_token)
    assert_raises(EssayGenerationRun::StaleExecution) { run.persist_stage!(old_token, 'supplement') { flunk 'stale result write' } }
    assert_equal replacement.token, EssayGenerationRun.request!(@grading, kind: 'supplement', manual: true, force: true).token
    assert_equal 1, EssayGenerationRun.where(essay_grading: @grading).count
  end

  test 'unknown result and long running tasks are not permission to issue paid reruns' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    token = run.token
    run.claim!(token)
    run.update_columns(started_at: 6.hours.ago)
    assert_not run.public_state[:can_retry]
    run.finish!(token, success: false, unknown: true)
    assert_equal 'unknown', run.reload.state
    assert_not run.public_state[:can_retry]
    assert_equal token, EssayGenerationRun.request!(@grading, kind: 'supplement', manual: true, force: true).token
    assert_empty EssayGenerationNotificationJob.jobs
  end

  test 'successful stages survive automatic retries and invalid outputs never replace stored feedback' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    run.claim!(run.token)
    run.persist_stage!(run.token, 'grading') { |record| record.update!(grading: { 'data' => { 'text' => 'preserved' } }) }
    run.finish!(run.token, success: false)
    assert_equal ['grading'], run.reload.completed_stages
    travel_to(run.next_retry_at + 1.second) do
      token = run.token
      run.claim!(token)
      service = EssayGradingService.new(@student.id, @grading.reload, generation: run, token: token)
      assert service.send(:stage_completed?, 'grading')
      assert_not service.send(:process_streaming_response, terminal({ 'text' => '{}' }), 'task', 'grading')
      assert_equal 'preserved', @grading.reload.grading.dig('data', 'text')
    end
  end

  test 'partial stream without terminal is unknown and failed terminal cannot be treated as success' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    run.claim!(run.token)
    service = EssayGradingSupplementPracticeService.new(@student.id, @grading, generation: run, token: run.token)
    assert_raises(EssayGenerationRun::OutcomeUnknown) { service.send(:process_streaming_response, [{ 'event' => 'text_chunk', 'data' => @questions.to_json }], 'task') }
    result = terminal({ 'text' => @questions }, status: 'failed')
    assert_not service.send(:process_streaming_response, result, 'task')
    assert_nil @grading.reload.grading['supplement_practice']
    assert service.send(:process_streaming_response, terminal({ 'text' => "```json\n#{@questions.to_json}\n```" }), 'task')
    run.finish!(run.token, success: true)
    assert_equal 'ready', SupplementPracticeAvailability.call(@grading.reload)[:state]
    assert_equal 1, SupplementPracticeParserService.new(@grading).parse['sections'].length
  end

  test 'valid existing supplement and saved student answers are never regenerated' do
    store_questions
    assert_nil EssayGenerationRun.request!(@grading, kind: 'supplement')
    post "#{@url}/draft", params: { answers: { sections: [] }, using_time: 12 }, headers: @headers, as: :json
    assert_response :ok, response.body
    saved = SupplementPracticeRecord.last.attributes
    assert_raises(EssayGenerationRun::Unavailable) { EssayGenerationRun.request!(@grading.reload, kind: 'supplement', force: true, manual: true) }
    assert_equal saved, SupplementPracticeRecord.last.attributes
  end

  test 'student retry is a real mutation and double clicks enqueue one run' do
    @grading.update_columns(grading: { 'supplement_practice' => { 'text' => '{broken' } })
    get @url, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal true, response.parsed_body.dig('generation', 'can_retry')
    assert_empty EssayGenerationJob.jobs, 'GET must never start work'
    post "#{@url}/retry", headers: @headers, as: :json
    assert_response :accepted, response.body
    assert_equal 'queued', response.parsed_body.dig('generation', 'state')
    post "#{@url}/retry", headers: @headers, as: :json
    assert_response :conflict
    assert_equal 1, EssayGenerationJob.jobs.length
    get @url, headers: @headers, as: :json
    assert_equal 'queued', response.parsed_body.dig('generation', 'state')
    %w[draft submit].each do |action|
      post "#{@url}/#{action}", params: { answers: { sections: [] } }, headers: @headers, as: :json
      assert_response :conflict
    end
    assert_empty @grading.supplement_practice_records
  end

  test 'retry enforces authentication ownership ready state and cooldown' do
    post "#{@url}/retry", as: :json
    assert_response :unauthorized
    other = GeneralUser.create!(email: "other-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(other, :general_user, nil)
    post "#{@url}/retry", headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    assert_response :forbidden
    store_questions
    post "#{@url}/retry", headers: @headers, as: :json
    assert_response :conflict
    @grading.update_columns(grading: {})
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    run.update_columns(state: 'failed', finished_at: Time.current)
    post "#{@url}/retry", headers: @headers, as: :json
    assert_response :conflict
    run.update_columns(finished_at: 2.minutes.ago)
    assert run.reload.public_state[:can_retry]
  end

  test 'comprehension persistence includes unanswered blanks and respects drafts' do
    @assignment.update_columns(category: 'comprehension', meta: { 'fill_in_the_blanks_visible' => true })
    @grading.update_columns(grading: { 'comprehension' => { 'questions' => [{ 'type' => 'multiple_choice', 'answer' => 'A', 'user_answer' => 'A' }, { 'type' => 'fill_in_the_blanks', 'blanks' => [{ 'id' => 'b1', 'answer' => 'word' }], 'user_answer' => nil }] } })
    @grading.reload.calculate_comprehension_score
    assert_equal 1, @grading.reload.score
    assert_equal 2, @grading.grading.dig('comprehension', 'full_score')
    @grading.update_columns(status: EssayGrading.statuses[:draft])
    @grading.calculate_comprehension_score
    assert_equal 'draft', @grading.reload.status
    assert_empty EssayGenerationJob.jobs
  end

  test 'create and submit callbacks enqueue once only after commit' do
    grading = EssayGrading.create!(general_user: @student, essay_assignment: @assignment, topic: 'New', essay: 'Response', status: :pending, grading: {}, general_context: {}, revised_essay: {}, meta: {})
    assert_equal 1, grading.essay_generation_runs.count
    assert_equal 1, EssayGenerationJob.jobs.length
    @grading.update_columns(status: EssayGrading.statuses[:draft])
    @grading.update!(status: :pending)
    assert_equal 1, @grading.essay_generation_runs.count
    assert_equal 2, EssayGenerationJob.jobs.length
    @grading.update!(topic: 'Changed title')
    assert_equal 2, EssayGenerationJob.jobs.length
  end

  test 'actual worker retries rejected main outputs but preserves successful context and revised essay' do
    @grading.update_columns(grading: { 'app_key' => 'test' }, general_context: { 'app_key' => 'test' }, revised_essay: { 'app_key' => 'test' })
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    calls = Hash.new(0)
    3.times do
      travel_to((run.reload.next_retry_at || Time.current) + 1.second) do
        token = run.token
        service = EssayGradingService.new(@student.id, @grading.reload, generation: run, token: token)
        stream = lambda do |_key, _payload, task|
          stage = task.end_with?('_grading') ? 'grading' : 'general_context'
          calls[stage] += 1
          [terminal({ 'text' => stage == 'grading' ? '{}' : 'Good work.' }), task]
        end
        completion = lambda do |*_args|
          calls['revised_essay'] += 1
          Struct.new(:code, :body).new(200, { answer: 'I am happy.' }.to_json)
        end
        service.stub(:execute_workflow_streaming, stream) do
          service.stub(:execute_completion, completion) do
            EssayGradingService.stub(:new, service) { EssayGenerationJob.new.perform(run.id, token) }
          end
        end
      end
    end
    assert_equal({ 'grading' => 3, 'general_context' => 1, 'revised_essay' => 1 }, calls)
    assert_equal 'failed', run.reload.state
    assert_equal 'stopped', @grading.reload.status
    assert_equal 'Good work.', @grading.general_context.dig('data', 'text')
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
  end

  test 'marking an active grading draft invalidates its worker token' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    token = run.token
    assert run.claim!(token)
    @grading.admin_mark_as_draft!
    assert_equal 'cancelled', run.reload.state
    assert_raises(EssayGenerationRun::StaleExecution) { run.persist_stage!(token, 'grading') { flunk 'cancelled result write' } }
    run.finish!(token, success: true)
    assert_equal 'draft', @grading.reload.status
    assert_empty EssayGenerationNotificationJob.jobs
    @grading.update!(status: :pending)
    assert_equal 'queued', run.reload.state
    assert_not_equal token, run.token
  end

  test 'valid main feedback becomes graded and durably queues only the independent supplement' do
    @grading.update_columns(grading: { 'app_key' => 'test' })
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    token = run.token
    feedback = { 'Overall Score' => 0, 'Full Score' => 9, 'Criterion 1' => { 'Grammar' => 0, 'Full Score' => 9, 'explanation' => 'Needs improvement.' }, 'Sentence1' => { 'sentence' => 'I am happy.', 'errors' => {} } }
    service = EssayGradingService.new(@student.id, @grading, generation: run, token: token)
    stream = ->(_key, _payload, task) { [terminal({ 'text' => feedback }), task] }
    worker = EssayGenerationJob.new
    service.stub(:execute_workflow_streaming, stream) do
      worker.stub(:notify_completion, true) do
        EssayGradingService.stub(:new, service) { worker.perform(run.id, token) }
      end
    end
    assert_equal 'ready', run.reload.state
    assert_equal 'graded', @grading.reload.status
    assert_equal 'queued', EssayGenerationRun.find_by!(essay_grading: @grading, kind: 'supplement').state
    assert_equal 2, EssayGenerationJob.jobs.length
    assert_empty EssayGenerationNotificationJob.jobs
  end

  test 'existing mailer shows supplement failure without claiming main grading stopped or including essay' do
    @grading.update_columns(essay: 'PRIVATE_STUDENT_ESSAY_SENTINEL')
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    run.update_columns(attempts: 3, state: 'failed')
    mail = AdminNotificationMailer.assignment_stopped_notification(@grading, generation: run)
    assert_includes mail.subject, 'Supplementary Exercise Failed'
    assert_includes mail.text_part.body.to_s, 'Attempts: 3'
    assert_includes mail.text_part.body.to_s, @grading.id
    assert_not_includes mail.encoded, 'PRIVATE_STUDENT_ESSAY_SENTINEL'
    assert_equal 'graded', @grading.reload.status
  end

  private

  def terminal(outputs, status: 'succeeded')
    [{ 'event' => 'workflow_finished', 'data' => { 'status' => status, 'outputs' => outputs } }]
  end

  def store_questions
    @grading.update_columns(grading: { 'supplement_practice' => { 'text' => @questions } })
  end
end
