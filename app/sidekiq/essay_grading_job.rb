# app/workers/essay_grading_worker.rb
class EssayGradingJob
  include Sidekiq::Worker

  def perform(essay_grading_id)
    essay_grading = EssayGrading.find(essay_grading_id)
    EssayGradingService.new(essay_grading.general_user_id, essay_grading).run_workflow
  end
end
