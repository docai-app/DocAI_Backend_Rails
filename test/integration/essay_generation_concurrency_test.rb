# frozen_string_literal: true

require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class EssayGenerationConcurrencyTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    raise 'Isolated test database required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1' && ActiveRecord::Base.connection_db_config.database.start_with?('listening_rails_isolated_test')
    @user = GeneralUser.create!(email: "race-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Race test', title: 'Race test', assignment: 'Test', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, essay: 'Test', topic: 'Race', status: :draft, grading: {}, general_context: {}, revised_essay: {}, meta: {})
    @grading.update_columns(status: EssayGrading.statuses[:graded])
  end

  teardown do
    @grading&.destroy!
    @assignment&.destroy!
    # No visits or memberships are created by this fixture. Avoid unrelated
    # analytics callbacks whose tables are outside this isolated test schema.
    @user&.delete
  end

  test 'simultaneous requests create one slot and concurrent workers claim it once' do
    gate = Queue.new
    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          EssayGenerationRun.request!(EssayGrading.find(@grading.id), kind: 'supplement', force: true, manual: true).token
        end
      end
    end
    4.times { gate << true }
    tokens = threads.map(&:value)
    assert_equal 1, tokens.uniq.length
    assert_equal 1, EssayGenerationRun.where(essay_grading: @grading).count
    run = EssayGenerationRun.find_by!(essay_grading: @grading)
    workers = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { EssayGenerationRun.find(run.id).claim!(run.token) }
      end
    end
    assert_equal 1, workers.map(&:value).count(true)
    assert_equal 1, run.reload.attempts
  end

  test 'stale queue replacement cannot race a successful worker claim' do
    run = EssayGenerationRun.request!(@grading, kind: 'supplement')
    10.times do
      old_token = SecureRandom.uuid
      run.update_columns(token: old_token, state: 'queued', queued_at: 3.hours.ago, finished_at: nil)
      gate = Queue.new
      claim = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          EssayGenerationRun.find(run.id).claim!(old_token)
        end
      end
      retry_request = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          EssayGenerationRun.request!(EssayGrading.find(@grading.id), kind: 'supplement', force: true, manual: true).token
        end
      end
      2.times { gate << true }
      claimed, resulting_token = claim.value, retry_request.value
      assert_not(claimed && resulting_token != old_token, 'a claimed original and a replacement must never both proceed')
    end
  end
end
