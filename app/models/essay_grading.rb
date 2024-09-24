# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_gradings
#
#  id                  :uuid             not null, primary key
#  essay               :text
#  topic               :string
#  status              :integer          default("pending"), not null
#  grading             :jsonb            not null
#  general_user_id     :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  essay_assignment_id :uuid
#  general_context     :jsonb            not null
#  using_time          :integer          default(0), not null
#  meta                :jsonb            not null
#
# Indexes
#
#  index_essay_gradings_on_essay_assignment_id  (essay_assignment_id)
#
# Foreign Keys
#
#  fk_rails_...  (essay_assignment_id => public.essay_assignments.id)
#  fk_rails_...  (general_user_id => public.general_users.id)
#
class EssayGrading < ApplicationRecord
  store_accessor :grading, :app_key, :data, :number_of_suggestion, :comprehension
  store_accessor :general_context, :app_key, :data

  store_accessor :meta, :newsfeed_id

  # 關聯
  belongs_to :general_user
  # belongs_to :essay_assignment, optional: true
  belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true
  delegate :category, to: :essay_assignment

  # 狀態枚舉
  enum status: { pending: 0, graded: 1, stopped: 2 }

  after_create :run_workflow, if: :need_to_run_workflow?
  after_create :calculate_comprehension_score, if: :is_comprehension?

  has_one_attached :file, service: :microsoft

  # 动态定义 comprehension getter 和 setter 方法
  %i[questions questions_count full_score score].each do |key|
    define_method(key) do
      comprehension && comprehension[key.to_s]
    end

    define_method("#{key}=") do |value|
      self.comprehension = (comprehension || {}).merge(key.to_s => value)
    end
  end

  # def upload_file(file)
  #   blob_service = Azure::Storage::Blob::BlobService.create
  #   container_name = 'your_container_name'
  #   blob_name = "essays/#{id}/#{file.original_filename}"

  #   content = file.read
  #   blob_service.create_block_blob(container_name, blob_name, content)
  # end

  def is_comprehension?
    category == 'comprehension'
  end

  def need_to_run_workflow?
    %w[essay speaking_essay speaking_conversation].include?(category)
  end

  def run_workflow
    # EssayGradingService.new(general_user_id, self).run_workflows
    EssayGradingJob.perform_async(id)
  end

  def modify_url
    uri = URI.parse(file.url)
    query_params = URI.decode_www_form(uri.query).to_h
    query_params.delete('rscd') # 删除 rscd 参数
    uri.query = URI.encode_www_form(query_params)
    uri.to_s
  end

  def transcribe_audio
    return nil
    return essay if essay.present?

    begin
      response = RestClient::Request.execute(
        method: :post,
        url: 'https://pormhub.m2mda.com/api/open_ai/transcribe_audio',
        payload: { audio_url: file.url }.to_json,
        headers: { content_type: :json, accept: :json },
        open_timeout: 60,   # 设置连接超时时间为 60 秒
        read_timeout: 300   # 设置读取超时时间为 120 秒
      )

      # 处理成功的响应
      response = JSON.parse(response.body) # 返回解析后的JSON数据
      self['essay'] = response['text']
      save
    rescue RestClient::ExceptionWithResponse => e
      # 处理失败的响应
      error_response = e.response
      raise "API request failed with response: #{error_response.code} #{error_response.body}"
    rescue StandardError => e
      # 处理其他错误
      raise "An error occurred: #{e.message}"
    end
  end

  def run_workflow_sync
    transcribe_audio # 如果唔需要，佢自己會 skip，多 call 唔怕
    EssayGradingService.new(general_user_id, self).run_workflows
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

  def calculate_essay_score
    # 檢查 grading 入邊有冇 Overall Score
    json_data = JSON.parse(self['grading']['data']['text'])
    score = json_data['Overall Score']
    return unless score.present?

    self['score'] = score
    save
  end

  def get_news_feed

    # 如果 meta 中有 self_upload_newsfeed，直接返回該數據
    return essay_assignment.get_news_feed if essay_assignment.get_news_feed.present?

    return nil if self['meta']['newsfeed_id'].nil?

    uri = URI.parse("https://ggform.examhero.com/api/v1/news_feeds/#{newsfeed_id}")
    response = Net::HTTP.get_response(uri)

    return unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
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
    self['score'] = score
    save
  end
end
