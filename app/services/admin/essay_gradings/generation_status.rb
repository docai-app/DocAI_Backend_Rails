# frozen_string_literal: true

module Admin
  module EssayGradings
    # Admin-only diagnostics, deliberately excluding provider credentials/output.
    class GenerationStatus
      def self.call(grading, kind: 'grading')
        run = grading.essay_generation_runs.detect { |item| item.kind == kind }
        return nil unless run

        context = run.provider_context.is_a?(Hash) ? run.provider_context : {}
        last_error = grading.meta.is_a?(Hash) ? grading.meta['last_grading_error'] : nil

        run.public_state.merge(
          stage: context['stage'], failure_code: run.failure_code,
          failure_stage: last_error.is_a?(Hash) ? last_error['stage'] : nil,
          finished_at: run.finished_at, recovery_checked_at: run.recovery_checked_at,
          missing_since: run.missing_since, resume_pending: run.resume_pending
        )
      end
    end
  end
end
