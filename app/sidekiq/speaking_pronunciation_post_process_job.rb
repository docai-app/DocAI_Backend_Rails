# frozen_string_literal: true

class SpeakingPronunciationPostProcessJob
  include Sidekiq::Worker

  def perform(essay_assignment_id, run_pinyin = true)
    essay_assignment = EssayAssignment.find_by(id: essay_assignment_id)
    unless essay_assignment&.speaking_pronunciation?
      Rails.logger.info(
        "[SpeakingPronunciationPostProcessJob] Skip assignment #{essay_assignment_id}: not found or not speaking_pronunciation"
      )
      return
    end

    essay_assignment.run_speaking_pronunciation_post_process!(run_pinyin: run_pinyin)
  rescue StandardError => e
    Rails.logger.error(
      "[SpeakingPronunciationPostProcessJob] Failed for assignment #{essay_assignment_id}: #{e.class} #{e.message}"
    )
    raise
  end
end
