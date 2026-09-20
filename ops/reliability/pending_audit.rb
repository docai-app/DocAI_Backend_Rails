# Read-only Rails runner. No provider POST, student content, credentials or writes.
require 'sidekiq/api'
Apartment::Tenant.switch('public') do
  snapshot = EssayGenerationQueueSnapshot.new
  all_pending = EssayGrading.where(status: :pending)
  current_pending = CurrentAcademicYearGradings.call(all_pending)
  rows = current_pending.includes(:essay_assignment, :essay_generation_runs)
  result = rows.map do |grading|
    runs = grading.essay_generation_runs.map do |run|
      { id: run.id, kind: run.kind, state: run.state, attempts: run.attempts,
        queue: snapshot.status(run), recovery_version: run.recovery_version,
        created_at: run.created_at, missing_since: run.missing_since,
        recovery_checked_at: run.recovery_checked_at,
        provider: run.provider_context['provider'], stage: run.provider_context['stage'],
        has_provider_id: run.provider_context['run_id'].present?,
        has_terminal: run.provider_context['terminal'].present? }
    end
    { id: grading.id, category: grading.essay_assignment&.category,
      created_at: grading.created_at, updated_at: grading.updated_at, runs: runs }
  end
  puts JSON.generate(at: Time.current, pending_count: all_pending.count, current_year_pending_count: result.length,
                     excluded_pending_count: all_pending.count - result.length,
                     unattributed_pending_count: CurrentAcademicYearGradings.unattributed(all_pending).count,
                     records: result,
                     queue_sizes: Sidekiq::Queue.all.to_h { |q| [q.name, q.size] },
                     schedules: Sidekiq.get_all_schedules.keys)
end
