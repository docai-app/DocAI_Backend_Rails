# frozen_string_literal: true

# app/workers/essay_grading_worker.rb
class EssayGradingJob
  include Sidekiq::Worker

  def perform(essay_grading_id)
    essay_grading = EssayGrading.find(essay_grading_id)
    essay_grading.transcribe_audio # function 自己有判斷需唔需要
    EssayGradingService.new(essay_grading.general_user_id, essay_grading).run_workflows
  end
end
