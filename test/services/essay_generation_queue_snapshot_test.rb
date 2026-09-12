require 'test_helper'
require 'minitest/mock'

class EssayGenerationQueueSnapshotTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  Job = Struct.new(:klass, :args)
  Run = Struct.new(:id, :token)
  Work = Struct.new(:job)

  def snapshot(work: [], queues: [], scheduled: [], retries: [])
    Sidekiq::WorkSet.stub(:new, work) do
      Sidekiq::Queue.stub(:all, queues) do
        Sidekiq::ScheduledSet.stub(:new, scheduled) do
          Sidekiq::RetrySet.stub(:new, retries) { yield EssayGenerationQueueSnapshot.new }
        end
      end
    end
  end

  test 'all live Sidekiq locations match exact run and token only' do
    job = Job.new('EssayGenerationJob', [7, 'token'])
    run = Run.new(7, 'token')
    [{work: [['pid', 'tid', Work.new(job)]]}, {queues: [[job]]}, {scheduled: [job]}, {retries: [job]}].each do |location|
      snapshot(**location) do |result|
        assert_equal :present, result.status(run)
        assert_equal :absent, result.status(Run.new(7, 'old'))
        assert_equal :absent, result.status(Run.new(8, 'token'))
      end
    end
    snapshot(queues: [[Job.new('OtherJob', [7, 'token'])]]) { |result| assert_equal :absent, result.status(run) }
  end

  test 'Redis failure and oversized observations never authorize recovery' do
    Sidekiq::WorkSet.stub(:new, -> { raise IOError }) do
      assert_equal :unknown, EssayGenerationQueueSnapshot.new.status(Run.new(7, 'token'))
    end
    jobs = Array.new(EssayGenerationQueueSnapshot::LIMIT + 1) { Job.new('OtherJob', []) }
    snapshot(queues: [jobs]) { |result| assert_equal :unknown, result.status(Run.new(7, 'token')) }
  end
end
