# frozen_string_literal: true

# == Schema Information
#
# Table name: assessment_records
#
#  id              :uuid             not null, primary key
#  title           :string
#  record          :jsonb
#  meta            :jsonb
#  recordable_type :string
#  recordable_id   :uuid
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_assessment_records_on_recordable  (recordable_type,recordable_id)
#
class AssessmentRecord < ApplicationRecord
  store_accessor :meta, :final_score
  store_accessor :record, :questions

  belongs_to :recordable, polymorphic: true

  after_create :calculate_score

  def calculate_score
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
    # self['meta']['final_score'] = score
    self['score'] = score
    self['questions_count'] = questions.count
    self['full_score'] = questions.count
    save
  end
end
