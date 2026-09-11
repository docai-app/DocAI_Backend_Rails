# frozen_string_literal: true

class EssayGenerationJob
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(run_id, token)
    run = EssayGenerationRun.find_by(id: run_id)
    return unless run&.claim!(token)

    grading = run.essay_grading
    if run.kind == 'supplement'
      success = EssayGradingSupplementPracticeService.new(grading.general_user_id, grading, generation: run, token: token).run_workflow
    else
      if grading.category == 'speaking_essay' && !run.completed_stages.include?('audio')
        success = SpeakingEssay::AudioAnalysisService.new(grading, generation: run, token: token).call
        unless success
          run.finish!(token, success: false)
          return
        end
      end
      success = EssayGradingService.new(grading.general_user_id, grading.reload, generation: run, token: token).run_workflows
    end
    run.finish!(token, success: success)
    if run.reload.state == 'ready' && run.kind == 'grading'
      # Webhook failure must not restart successful, billable workflows.
      begin
        notify_completion(grading.reload)
      rescue StandardError => e
        Rails.logger.error("[EssayGenerationJob] Webhook unavailable run=#{run_id} error=#{e.class}")
      end
    end
  rescue EssayGenerationRun::OutcomeUnknown
    run&.finish!(token, success: false, unknown: true)
  rescue EssayGenerationRun::StaleExecution
    # Superseded queue deliveries are harmless and must not mutate the new run.
    nil
  rescue StandardError => e
    Rails.logger.error("[EssayGenerationJob] run=#{run_id} error=#{e.class}")
    run&.finish!(token, success: false)
  end

  private

  def notify_completion(grading)
    grading.call_webhook
  end
end
