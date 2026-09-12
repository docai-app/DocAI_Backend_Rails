require 'sidekiq/api'
require 'set'

# Read-only, bounded observation. Never deletes/reorders jobs or controls workers.
# Sidekiq iteration is not atomic: absence needs two observations AND a DB fence.
class EssayGenerationQueueSnapshot
  LIMIT = 20_000

  def initialize
    @present = Set.new
    @complete = false
    count = 0
    visit = lambda do |job|
      count += 1
      raise 'Queue snapshot limit reached' if count > LIMIT
      @present << job.args.first(2) if job.klass == 'EssayGenerationJob'
    end
    Sidekiq::WorkSet.new.each { |_pid, _tid, work| visit.call(work.job) }
    Sidekiq::Queue.all.each { |queue| queue.each { |job| visit.call(job) } }
    [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each { |set| set.each { |job| visit.call(job) } }
    @complete = true
  rescue StandardError => e
    Rails.logger.warn("[EssayGenerationRecovery] Queue observation unavailable: #{e.class}")
  end

  def status(run)
    return :present if @present.include?([run.id, run.token])
    @complete ? :absent : :unknown
  end
end
