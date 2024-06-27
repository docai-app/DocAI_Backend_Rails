class EssayGrading < ApplicationRecord

  store_accessor :grading, :app_key, :data
  # 關聯
  belongs_to :general_user

  # 狀態枚舉
  enum status: { pending: 0, graded: 1, reviewed: 2 }

  after_create :run_workflow

  def run_workflow
    # EssayGradingService.new(general_user_id, self).run_workflow
    EssayGradingWorker.perform_async(id, general_user_id)
  end

end
