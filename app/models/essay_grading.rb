class EssayGrading < ApplicationRecord
  store_accessor :grading, :app_key, :data, :number_of_suggestion
  # 關聯
  belongs_to :general_user
  # belongs_to :essay_assignment, optional: true
  belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true

  # 狀態枚舉
  enum status: { pending: 0, graded: 1, stopped: 2 }

  after_create :run_workflow

  def run_workflow
    # EssayGradingService.new(general_user_id, self).run_workflow
    EssayGradingJob.perform_async(id)
  end

  def run_workflow_sync
    EssayGradingService.new(general_user_id, self).run_workflow
  end

  # 定義遞歸方法來計算所有 errors 的數量
  def count_errors(hash)
    count = 0
    hash.each do |key, value|
      if key == 'errors' && value.is_a?(Hash)
        count += value.size
      elsif value.is_a?(Hash)
        count += count_errors(value)
      end
    end
    count
  end

  def get_number_of_suggestion
    json = JSON.parse(grading['data']['text'])
    count_errors(json)
  end
end
