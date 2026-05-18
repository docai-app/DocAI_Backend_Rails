# frozen_string_literal: true

# app/workers/essay_grading_worker.rb
class EssayGradingJob
  include Sidekiq::Worker

  sidekiq_retries_exhausted do |msg, ex|
    essay_grading = EssayGrading.find_by(id: msg['args']&.first)
    next unless essay_grading&.category == 'speaking_essay'
    next if essay_grading.draft?

    Rails.logger.error("[EssayGradingJob] Speaking essay retries exhausted for #{essay_grading.id}: #{ex.message}")
    essay_grading.update(status: 'stopped')

    begin
      AdminNotificationMailer.assignment_stopped_notification(essay_grading).deliver_later
    rescue StandardError => notification_error
      Rails.logger.error("[EssayGradingJob] Failed to send stopped notification: #{notification_error.message}")
    end
  end

  def perform(essay_grading_id)
    essay_grading = EssayGrading.find(essay_grading_id)

    if essay_grading.category == 'speaking_essay'
      prepare_speaking_essay_audio!(essay_grading)
      essay_grading.reload
    else
      essay_grading.transcribe_audio # function 自己有判斷需唔需要
    end

    EssayGradingService.new(essay_grading.general_user_id, essay_grading).run_workflows
    if essay_grading.essay_assignment && essay_grading.essay_assignment.category == 'essay'
      EssayGradingSupplementPracticeService.new(essay_grading.general_user_id, essay_grading).run_workflow
    end
  end

  private

  def prepare_speaking_essay_audio!(essay_grading)
    SpeakingEssay::AudioAnalysisService.new(essay_grading).call
  rescue StandardError => e
    Rails.logger.error("[EssayGradingJob] Speaking essay audio analysis failed for #{essay_grading.id}: #{e.message}")
    Rails.logger.error("[EssayGradingJob] #{e.backtrace.first(5).join("\n")}") if e.backtrace
    raise
  end
end
