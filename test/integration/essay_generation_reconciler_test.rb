require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class EssayGenerationReconcilerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @user = GeneralUser.create!(email: "reconcile-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, title: 'Recovery', topic: 'Recovery', assignment: 'Test', category: :essay, rubric: {name: 'Test'}, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Recovery', essay: 'Keep my work.', status: :draft, grading: {'app_key'=>'local-test-key'}, general_context: {}, revised_essay: {}, meta: {})
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    @run = EssayGenerationRun.request!(@grading, kind: 'grading')
    @run.update_columns(queued_at: 3.hours.ago)
    EssayGenerationJob.clear
    EssayGenerationNotificationJob.clear
    @snapshot = Object.new
    def @snapshot.status(_run); :absent; end
    @checker = EssayGenerationReconciler.new(snapshot: @snapshot)
  end

  def missing_twice
    @checker.call(@run.reload)
    travel 5.minutes do
      @checker.call(@run.reload)
    end
  end

  def running(stage: nil, provider: 'opaque')
    @run.claim!(@run.token)
    @run.begin_provider!(@run.token, stage, provider: provider, app_key: 'local-test-key') if stage
    @run.update_columns(started_at: 3.hours.ago)
  end

  def workflow(status: 'succeeded', outputs: {'text'=>'context'})
    {'event'=>'workflow_finished', 'data'=>{'id'=>@workflow_id, 'status'=>status, 'outputs'=>outputs}}
  end

  test 'lost queue needs two observations and preserves successful stages' do
    old_token = @run.token
    @run.update_columns(completed_stages: ['grading'])
    @checker.call(@run)
    assert_empty EssayGenerationJob.jobs
    travel 5.minutes do
      @checker.call(@run.reload)
    end
    assert_equal 1, EssayGenerationJob.jobs.length
    assert_not_equal old_token, @run.reload.token
    assert_equal ['grading'], @run.completed_stages
    assert_equal 1, @run.recovery_count
    assert_not @run.claim!(old_token)
    assert_equal 'pending', @grading.reload.status
  end

  test 'present work including scheduled or retry set is never replaced' do
    [:present, :unknown].each do |value|
      old = @run.token
      @snapshot.stub(:status, value) { missing_twice }
      assert_equal old, @run.reload.token
      assert_nil @run.missing_since
      assert_empty EssayGenerationJob.jobs
    end
  end

  test 'recent and future scheduled work is not recovered' do
    @run.update_columns(state: 'retry_wait', queued_at: 5.hours.ago, next_retry_at: 1.hour.from_now)
    missing_twice
    assert_empty EssayGenerationJob.jobs
  end

  test 'worker claim between observations wins over recovery' do
    @checker.call(@run)
    token = @run.token
    assert @run.claim!(token)
    travel 5.minutes do
      @checker.call(@run.reload)
    end
    assert_equal token, @run.reload.token
    assert_equal 'running', @run.state
    assert_empty EssayGenerationJob.jobs
  end

  test 'lost worker before provider boundary can be safely resumed' do
    running
    old = @run.token
    missing_twice
    assert_equal 'queued', @run.reload.state
    assert_equal 1, @run.attempts
    assert_not_equal old, @run.token
    assert_raises(EssayGenerationRun::StaleExecution) { @run.begin_provider!(old, 'grading') }
  end

  test 'untracked legacy running is not automatically adopted' do
    running
    @run.update_columns(recovery_version: 0)
    missing_twice
    assert_equal 'unknown', @run.reload.state
    assert @run.public_state[:requires_attention]
    assert_empty EssayGenerationJob.jobs
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
  end

  test 'opaque in flight request becomes review required without paid repeat' do
    running(stage: 'audio')
    missing_twice
    assert_equal 'unknown', @run.reload.state
    assert @run.attention_required_at
    assert_not @run.public_state[:can_retry]
    assert_empty EssayGenerationJob.jobs
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
    missing_twice
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
  end

  test 'queue recovery cannot loop forever even if dispatch always disappears' do
    3.times do
      @run.update_columns(queued_at: 3.hours.ago, missing_since: nil)
      missing_twice
    end
    assert_equal 2, @run.reload.recovery_count
    assert_equal 2, EssayGenerationJob.jobs.length
    assert_equal 'failed', @run.state
    assert_equal 'stopped', @grading.reload.status
    assert_equal 1, EssayGenerationNotificationJob.jobs.length
  end

  test 'crashed third execution without pending provider cannot get a fourth execution' do
    running
    @run.update_columns(attempts: 3)
    missing_twice
    assert_equal 'failed', @run.reload.state
    assert_empty EssayGenerationJob.jobs
  end

  test 'original terminal response is recovered without new provider request and keeps attempt count' do
    running(stage: 'grading', provider: 'workflow')
    @workflow_id = SecureRandom.uuid
    @run.observe_provider!(@run.token, {'event'=>'workflow_started','data'=>{'id'=>@workflow_id}})
    lookup = Object.new
    result = workflow
    lookup.define_singleton_method(:lookup) { |id, **_args| raise 'wrong id' unless id == result['data']['id']; result['data'] }
    @checker = EssayGenerationReconciler.new(snapshot: @snapshot, provider_lookup: lookup)
    missing_twice
    assert_equal 'queued', @run.reload.state
    assert @run.resume_pending
    assert @run.claim!(@run.token)
    assert_equal 1, @run.reload.attempts
    service = EssayGradingService.new(@user.id, @grading.reload, generation: @run, token: @run.token)
    Net::HTTP.stub(:new, ->(*) { flunk 'must never POST recovered workflow' }) do
      events, = service.send(:execute_workflow_streaming, 'local-test-key', {}, "#{@grading.id}_grading")
      assert_equal [result], events
    end
  end

  test 'cached invalid supplement is still rejected by actual parser' do
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    @run.update_columns(kind: 'supplement')
    running(stage: 'supplement', provider: 'workflow')
    @workflow_id = SecureRandom.uuid
    @run.observe_provider!(@run.token, workflow(outputs: {'text'=>'{}'}))
    missing_twice
    assert @run.reload.claim!(@run.token)
    service = EssayGradingSupplementPracticeService.new(@user.id, @grading, generation: @run, token: @run.token)
    Net::HTTP.stub(:new, ->(*) { flunk 'must not regenerate' }) { assert_not service.run_workflow }
    assert_nil @grading.reload.grading['supplement_practice']
  end

  test 'provider still running or unavailable never grants paid retry' do
    running(stage: 'grading', provider: 'workflow')
    @workflow_id = SecureRandom.uuid
    @run.observe_provider!(@run.token, {'workflow_run_id'=>@workflow_id})
    lookup = Object.new
    id = @workflow_id
    lookup.define_singleton_method(:lookup) { |*, **| {'id'=>id,'status'=>'running'} }
    @checker = EssayGenerationReconciler.new(snapshot: @snapshot, provider_lookup: lookup)
    old = @run.token
    missing_twice
    assert_equal old, @run.reload.token
    assert_empty EssayGenerationJob.jobs
    lookup.define_singleton_method(:lookup) { |*, **| nil }
    missing_twice
    assert_equal 'unknown', @run.reload.state
    assert @run.attention_required_at
    assert_empty EssayGenerationJob.jobs
  end

  test 'provider key change requires review and never queries another app' do
    running(stage: 'grading', provider: 'workflow')
    @run.observe_provider!(@run.token, {'workflow_run_id'=>SecureRandom.uuid})
    @grading.update_columns(grading: {'app_key'=>'different-local-key'})
    DifyWorkflowRecovery.stub(:lookup, ->(*) { flunk 'wrong app' }) { missing_twice }
    assert_equal 'unknown', @run.reload.state
  end

  test 'disabled scanner does not inspect queues or enqueue recovery' do
    previous = ENV['AI_ENGLISH_RECOVERY_ENABLED']
    ENV['AI_ENGLISH_RECOVERY_ENABLED'] = 'false'
    EssayGenerationQueueSnapshot.stub(:new, -> { flunk 'disabled must not query redis' }) { EssayGenerationRecoveryJob.new.perform }
  ensure
    previous ? ENV['AI_ENGLISH_RECOVERY_ENABLED'] = previous : ENV.delete('AI_ENGLISH_RECOVERY_ENABLED')
  end

  test 'stale audio and speaking scoring failures cannot overwrite current error history' do
    @assignment.update_columns(category: 'speaking_essay')
    running
    old_token = @run.token
    @run.update_columns(token: SecureRandom.uuid)
    @grading.record_grading_error!(stage: 'current', message: 'Preserve this error')
    before = @grading.reload.meta.deep_dup
    service = SpeakingEssay::AudioAnalysisService.new(@grading, generation: @run, token: old_token)
    assert_raises(EssayGenerationRun::StaleExecution) { service.call } # Missing audio is a failure path, not a provider call.
    scoring = SpeakingEssay::ScoringService.new(@grading, generation: @run, token: old_token)
    scoring.stub(:speaking_analysis, -> { raise 'Old worker failure' }) do
      assert_raises(EssayGenerationRun::StaleExecution) { scoring.call }
    end
    assert_equal before, @grading.reload.meta
  end

  test 'review email wording is not a false stopped message and is deduplicated' do
    running(stage: 'audio')
    missing_twice
    message = AdminNotificationMailer.assignment_stopped_notification(@grading.reload, generation: @run.reload).message
    assert_includes message.subject, 'Needs Review'
    assert_includes message.html_part ? message.html_part.decoded : message.body.decoded, 'no new generation was started'
    mail = Minitest::Mock.new
    mail.expect(:message, Struct.new(:encoded).new('rendered'))
    mail.expect(:deliver_now, true)
    AdminNotificationMailer.stub(:assignment_stopped_notification, mail) do
      2.times { EssayGenerationNotificationJob.new.perform(@run.id, @run.token) }
    end
    mail.verify
    assert @run.reload.attention_notified_at
    assert_nil @run.notified_at
  end

  test 'saved final checkpoint can finish third attempt without regeneration' do
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    @run.update_columns(kind: 'supplement')
    running
    @run.update_columns(attempts: 3, completed_stages: ['supplement'])
    missing_twice
    assert_equal 'queued', @run.reload.state
    assert @run.resume_pending
    Net::HTTP.stub(:new, ->(*) { flunk 'saved work must not regenerate' }) do
      EssayGenerationJob.new.perform(@run.id, @run.token)
    end
    assert_equal 'ready', @run.reload.state
    assert_equal 3, @run.attempts
    assert_equal 'graded', @grading.reload.status
  end

  test 'valid recovered supplement goes through actual worker validation on third attempt' do
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    @run.update_columns(kind: 'supplement')
    running(stage: 'supplement', provider: 'workflow')
    questions = {'quizTitle'=>'Practice', 'sections'=>[{'topic'=>'Verbs', 'type'=>'multiple_choice',
      'questions'=>[{'question'=>'I __ happy.', 'options'=>['am', 'is'], 'answer'=>'am'}]}]}
    @run.observe_provider!(@run.token, workflow(outputs: {'text'=>questions.to_json}))
    @run.update_columns(attempts: 3)
    missing_twice
    # The replacement can also disappear from Redis before being claimed.
    @run.update_columns(queued_at: 3.hours.ago)
    missing_twice
    assert_equal 2, @run.reload.recovery_count
    assert @run.provider_context['terminal'].present?
    assert @run.resume_pending
    Net::HTTP.stub(:new, ->(*) { flunk 'must reuse provider output' }) do
      EssayGenerationJob.new.perform(@run.id, @run.reload.token)
    end
    assert_equal 'ready', @run.reload.state
    assert_equal 3, @run.attempts
    assert_equal 'ready', SupplementPracticeAvailability.call(@grading.reload)[:state]
    assert_equal 'graded', @grading.status
  end

  test 'repeated scans cannot enqueue two replacements from the same observation' do
    missing_twice
    token = @run.reload.token
    3.times { @checker.call(EssayGenerationRun.find(@run.id)) }
    assert_equal token, @run.reload.token
    assert_equal 1, EssayGenerationJob.jobs.length
  end

  test 'provider completion between lookup and write wins over recovery' do
    running(stage: 'grading', provider: 'workflow')
    @workflow_id = SecureRandom.uuid
    @run.observe_provider!(@run.token, {'workflow_run_id'=>@workflow_id})
    token = @run.token
    run = @run
    lookup = Object.new
    lookup.define_singleton_method(:lookup) do |id, **_args|
      run.persist_stage!(token, 'grading') { |_record| nil }
      run.finish!(token, success: true)
      {'id'=>id, 'status'=>'succeeded', 'outputs'=>{}}
    end
    @checker = EssayGenerationReconciler.new(snapshot: @snapshot, provider_lookup: lookup)
    missing_twice
    assert_equal 'ready', @run.reload.state
    assert_equal token, @run.token
    assert_equal 0, @run.recovery_count
    assert EssayGenerationJob.jobs.none? { |job| job['args'].first == @run.id }
  end

  test 'enabled scanner respects activation cutoff and excludes Listening' do
    previous = ENV.values_at('AI_ENGLISH_RECOVERY_ENABLED', 'AI_ENGLISH_RECOVERY_ENABLED_AT')
    ENV['AI_ENGLISH_RECOVERY_ENABLED'] = 'true'
    ENV['AI_ENGLISH_RECOVERY_ENABLED_AT'] = 1.day.ago.iso8601
    @run.update_columns(created_at: 2.days.ago)
    EssayGenerationQueueSnapshot.stub(:new, @snapshot) do
      EssayGenerationRecoveryJob.new.perform
      assert_nil @run.reload.recovery_checked_at
      @run.update_columns(created_at: 3.hours.ago)
      @assignment.update_columns(category: 'listening')
      EssayGenerationRecoveryJob.new.perform
      assert_nil @run.reload.recovery_checked_at
      @assignment.update_columns(category: 'essay')
      EssayGenerationRecoveryJob.new.perform
      assert @run.reload.missing_since
      travel 5.minutes do
        EssayGenerationRecoveryJob.new.perform
      end
      assert_equal 1, @run.reload.recovery_count
    end
  ensure
    %w[AI_ENGLISH_RECOVERY_ENABLED AI_ENGLISH_RECOVERY_ENABLED_AT].zip(previous).each do |key, value|
      value ? ENV[key] = value : ENV.delete(key)
    end
  end

  test 'stale worker cannot clear grading error history' do
    running
    token = @run.token
    missing_twice
    service = EssayGradingService.new(@user.id, @grading, generation: @run, token: token)
    @grading.stub(:clear_grading_errors!, -> { flunk 'stale worker mutated metadata' }) do
      assert_raises(EssayGenerationRun::StaleExecution) { service.run_workflows }
    end
  end
end
