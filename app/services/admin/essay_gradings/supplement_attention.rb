# frozen_string_literal: true

module Admin
  module EssayGradings
    # Same two-hour threshold and waiting clock as the operations report.
    # This scope only adds current-year, already-graded essay submissions.
    class SupplementAttention
      def self.call(now: Time.current)
        runs = EssayGenerationRun.where(kind: 'supplement', state: %w[failed unknown queued retry_wait running checking])
        stale = runs.where("COALESCE(CASE WHEN state IN ('running', 'checking') THEN started_at WHEN state = 'retry_wait' THEN next_retry_at END, queued_at, created_at) < ?", now - 2.hours)
        ids = runs.where(state: %w[failed unknown]).or(stale).select(:essay_grading_id)
        CurrentAcademicYearGradings.call(now: now).where(status: :graded, id: ids)
          .where(essay_assignments: { category: 'essay' })
      end
    end
  end
end
