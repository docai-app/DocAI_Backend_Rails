require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class EssayGenerationRecoveryHealthTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  setup do
    @previous = ENV.values_at('AI_ENGLISH_RECOVERY_ENABLED', 'AI_ENGLISH_RECOVERY_ENABLED_AT')
    ENV['AI_ENGLISH_RECOVERY_ENABLED'] = 'true'
    ENV['AI_ENGLISH_RECOVERY_ENABLED_AT'] = 1.day.ago.iso8601
    @user = GeneralUser.create!(email: "health-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, assignment: 'Test', title: 'Test', topic: 'Test', category: :essay, rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Test', essay: 'Test.', status: :draft, grading: {}, meta: {})
    @run = EssayGenerationRun.request!(@grading, kind: 'grading')
    @run.update_columns(queued_at: 3.hours.ago)
    @health = []
    @job = EssayGenerationRecoveryJob.new
  end
  teardown do
    %w[AI_ENGLISH_RECOVERY_ENABLED AI_ENGLISH_RECOVERY_ENABLED_AT].zip(@previous).each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
  test 'per-record recovery errors are not reported as a clean scan' do
    snapshot = Object.new
    checker = Object.new
    checker.define_singleton_method(:call) { |_run| raise IOError, 'controlled failure' }
    recorder = ->(state, **fields) { @health << [state, fields] }
    @job.stub(:record_health, recorder) do
      EssayGenerationQueueSnapshot.stub(:new, snapshot) do
        EssayGenerationReconciler.stub(:new, ->(**_options) { checker }) { @job.perform }
      end
    end
    assert_equal 'running', @health.first.first
    assert_equal 'completed_with_errors', @health.last.first
    assert_equal '1', @health.last.last[:error_count]
    assert_equal '1', @health.last.last[:checked_count]
  end
  test 'a failed scan records failure and re-raises for normal Sidekiq visibility' do
    @job.stub(:record_health, ->(state, **fields) { @health << [state, fields] }) do
      EssayGenerationQueueSnapshot.stub(:new, -> { raise IOError, 'controlled outage' }) do
        assert_raises(IOError) { @job.perform }
      end
    end
    assert_equal 'failed', @health.last.first
    assert_equal 'IOError', @health.last.last[:error_class]
  end
end
