# frozen_string_literal: true
raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AssignmentDraftConcurrencyTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false
  parallelize(workers: 1)

  test 'independent database connections serialize opening, submission and stale saves' do
    10.times do
      user = GeneralUser.create!(email: "draft-race-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
      assignment = EssayAssignment.create!(general_user: user, category: 'essay', title: 'Race', topic: 'Race', assignment: 'Race', rubric: { 'name' => 'Test' }, meta: {})
      session = -> { AssignmentDraftSession.new(assignment: assignment, user: user) }
      ids = race { session.call.prepare(SecureRandom.uuid).id }
      assert_equal 1, ids.uniq.size
      assert_equal 0, assignment.reload.number_of_submission
      key = SecureRandom.uuid
      payload = { 'status' => 'pending', 'essay' => 'The same submission.' }
      results = race do
        session.call.write(payload, row: EssayGrading.find(ids.first), request_id: key, revision: 0) { |row| row.assign_attributes(payload) }.id
      end
      assert_equal [ids.first], results.uniq
      assert_equal 1, assignment.essay_gradings.count
      assert_equal 0, assignment.essay_gradings.where(status: :draft).count
      assert_equal 1, assignment.reload.number_of_submission
      second = session.call.prepare(SecureRandom.uuid)
      actions = Queue.new
      actions << payload.merge('status' => 'draft')
      actions << payload
      outcomes = race do
        attrs = actions.pop
        begin
          session.call.write(attrs, row: EssayGrading.find(second.id), request_id: SecureRandom.uuid, revision: 0) { |row| row.assign_attributes(attrs) }
          :saved
        rescue AssignmentDraftSession::Conflict
          :conflict
        end
      end
      assert_equal [:conflict, :saved], outcomes.sort
      if second.reload.draft?
        session.call.write(payload, row: second, request_id: SecureRandom.uuid, revision: 1) { |row| row.assign_attributes(payload) }
      end
      assert_equal 0, assignment.essay_gradings.where(status: :draft).count
      assert_equal 2, assignment.reload.number_of_submission
    ensure
      if assignment
        assignment.essay_gradings.destroy_all
        assignment.destroy!
      end
      GeneralUser.where(id: user.id).delete_all if user
    end
  end

  private

  def race
    ready, go = Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          yield
        end
      end
    end
    2.times { ready.pop }
    2.times { go << true }
    threads.map(&:value)
  end
end
