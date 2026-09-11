# frozen_string_literal: true

# app/workers/essay_grading_worker.rb
class EssayGradingJob
  include Sidekiq::Worker

  sidekiq_options retry: false

  def perform(essay_grading_id)
    grading = EssayGrading.find_by(id: essay_grading_id)
    return unless grading && !grading.draft?

    # Old queued deliveries enter the same slot as the new job/manual API.
    EssayGenerationRun.request!(grading, kind: 'grading')
  end
end
