# frozen_string_literal: true

class EssayGrading < ApplicationRecord
  store_accessor :grading, :app_key, :data, :number_of_suggestion, :comprehension
  # store_accessor :comprehension, :questions, :questions_count, :full_score, :score
  # 關聯
  belongs_to :general_user
  # belongs_to :essay_assignment, optional: true
  belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true
  delegate :category, to: :essay_assignment

  # 狀態枚舉
  enum status: { pending: 0, graded: 1, stopped: 2 }

  after_create :run_workflow, if: :need_to_run_workflow?

  after_create :calculate_comprehension_score, if: :is_comprehension?

  # 动态定义 comprehension getter 和 setter 方法
  %i[questions questions_count full_score score].each do |key|
    define_method(key) do
      self.comprehension && self.comprehension[key.to_s]
    end

    define_method("#{key}=") do |value|
      self.comprehension = (self.comprehension || {}).merge(key.to_s => value)
    end
  end

  def is_comprehension?
    category == "comprehension"
  end

  def need_to_run_workflow?
    category in ["essay", "speaking_essay"]
  end

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

  def calculate_comprehension_score
    # 初始化分数
    score = 0

    # 遍历所有问题
    questions.each do |question|
      # 比较正确答案和用户答案
      if question['answer'] == question['user_answer']
        # 如果答案正确，分数增加1
        score += 1
      end
    end

    # 返回最终分数
    self['grading']['comprehension']['score'] = score
    self['grading']['comprehension']['questions_count'] = questions.count
    self['grading']['comprehension']['full_score'] = questions.count
    self['status'] = 'graded'
    save
  end

end
