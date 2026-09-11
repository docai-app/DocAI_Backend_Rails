# frozen_string_literal: true

class SupplementPracticeAvailability
  def self.call(grading)
    run = EssayGenerationRun.find_by(essay_grading_id: grading.id, kind: 'supplement')
    return run.public_state if run && run.state != 'ready'

    questions = SupplementPracticeValidator.parse(grading)
    return { state: 'ready', can_retry: false } if questions

    # Old missing output has no authoritative queue history. Never infer failure
    # from nil alone, and never turn a GET into a paid generation request.
    { state: 'unknown', can_retry: false }
  rescue JSON::ParserError, ArgumentError, OldDataFormatError
    allowed = grading.graded? && !grading.supplement_practice_records.exists? &&
              (!run || !run.finished_at || run.finished_at <= 1.minute.ago)
    { state: 'failed', can_retry: allowed }
  end
end
