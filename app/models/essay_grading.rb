# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_gradings
#
#  id                          :uuid             not null, primary key
#  essay                       :text
#  topic                       :string
#  status                      :integer          default("pending"), not null
#  grading                     :jsonb            not null
#  general_user_id             :uuid             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  essay_assignment_id         :uuid
#  general_context             :jsonb            not null
#  using_time                  :integer          default(0), not null
#  meta                        :jsonb            not null
#  score                       :decimal(, )
#  sentence_builder            :jsonb
#  submission_class_name       :string
#  submission_class_number     :string
#  submission_school_id        :uuid
#  submission_academic_year_id :uuid
#
# Indexes
#
#  index_essay_gradings_on_essay_assignment_id  (essay_assignment_id)
#
# Foreign Keys
#
#  fk_rails_...  (essay_assignment_id => essay_assignments.id)
#  fk_rails_...  (general_user_id => general_users.id)
#
class EssayGrading < ApplicationRecord
  store_accessor :grading, :app_key, :data, :number_of_suggestion, :comprehension, :sentence_builder,
                 :speaking_pronunciation_sentences, :supplement_practice
  store_accessor :general_context, :app_key, :data

  store_accessor :meta, :newsfeed_id, :transformed_newsfeed

  # 關聯
  belongs_to :general_user
  belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true
  belongs_to :submission_school, class_name: 'School', optional: true
  belongs_to :submission_academic_year, class_name: 'SchoolAcademicYear', optional: true
  delegate :category, to: :essay_assignment

  # 狀態枚舉
  enum status: { pending: 0, graded: 1, stopped: 2 }

  after_create :run_workflow, if: :need_to_run_workflow?
  after_create :calculate_comprehension_score, if: :is_comprehension?
  after_create :calculate_speaking_pronunciation_score, if: :is_speaking_pronunciation?

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

  def is_speaking_pronunciation?
    category == 'speaking_pronunciation'
  end

  def need_to_run_workflow?
    %w[essay speaking_essay speaking_conversation sentence_builder].include?(category)
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
    if essay_assignment.get_news_feed.present?
      news_feed = essay_assignment.get_news_feed
      result = {}
      result['data'] = news_feed.key?('data') ? news_feed['data'] : news_feed
      return result
    end

    return nil if self['meta']['newsfeed_id'].nil?

    uri = URI.parse("https://ggform.examhero.com/api/v1/news_feeds/#{newsfeed_id}")
    response = Net::HTTP.get_response(uri)

    return unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def calculate_speaking_pronunciation_score
    threshold = essay_assignment.speaking_pronunciation_pass_score
    total_score = 0

    # 遍历每个 speaking_pronunciation_sentence
    grading['speaking_pronunciation_sentences'].each do |sentence_data|
      # 如果 score 大于 threshold，则得1分
      if sentence_data['result']['pronunciation_accuracy'].to_i >= threshold.to_i
        total_score += sentence_data['result']['pronunciation_accuracy'].to_i
      end
    end

    # 设置总分

    self['score'] = ((total_score.to_f / self['grading']['speaking_pronunciation_sentences'].count)).round
    self['status'] = 'graded'
    save
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

    # 呼叫 webhook
    call_webhook
  end

  def calculate_sentence_builder_score
    return { full_score: nil, score: nil } if self['status'] != 'graded'

    if self['grading']['sentence_builder'].is_a?(Array)
      # 遍历数组，检查每个元素是否有 score
      sentence_builder_data = self['grading']['sentence_builder'].find { |item| item['score'].present? }
      if sentence_builder_data
        return {
          full_score: sentence_builder_data['full_score'],
          score: sentence_builder_data['score']
        }
      end
    elsif self['grading']['sentence_builder'] && self['grading']['sentence_builder']['score'].present?
      # 如果是哈希，直接访问
      return {
        full_score: self['grading']['sentence_builder']['full_score'],
        score: self['grading']['sentence_builder']['score']
      }
    end

    response = JSON.parse(grading['data']['text'])
    total_score = response['results'].size
    score = 0

    # 遍歷每個句子結果
    response['results'].each do |result|
      # 檢查是否有錯誤
      score += 1 if result['errors'].all? { |error| error['error1'] == 'Correct' }
    end

    # 設置分數
    self['grading']['sentence_builder'] ||= {}
    self['grading']['score'] = score
    self['grading']['full_score'] = total_score
    self['score'] = score
    save

    # 返回 full_score 和 score
    { full_score: total_score, score: }
  end

  def call_webhook
    # 从 general_user 的 konnecai_tokens 中获取对应 category 的 token
    token = general_user.konnecai_tokens[essay_assignment.category]

    # 确保 token 存在
    unless token
      Rails.logger.error("No token found for category: #{essay_assignment.category}")
      return
    end

    webhook_url = ENV['WEBHOOK_URL']

    # 准备简化后的请求数据
    payload = {
      record: {
        Id: id,
        User: general_user.nickname,
        Class: general_user.banbie,
        Number: general_user.class_no,
        "Submitted Time": created_at,
        "Time Taken(s)": using_time,
        Status: status,
        Category: category
      }
    }

    if category == 'comprehension'
      payload[:record]['Full Score'] = grading.dig('comprehension', 'full_score')
      payload[:record][:Score] = grading.dig('comprehension', 'score')
    elsif category == 'sentence_builder'
      payload[:record]['Full Score'] = grading['full_score']
      payload[:record][:Score] = grading['score']
    else
      grading_data = JSON.parse(grading['data']['text'])
      payload[:record][:Score] = grading_data['Overall Score']
      payload[:record]['Full Score'] = grading_data['Full Score']
      payload[:record][:Rubric] = essay_assignment.rubric['name']
      grading_data.each do |key, value|
        next unless key.start_with?('Criterion')

        # 遍歷 value，排除 'Full Score' 和 'explanation'
        value.each do |criterion_name, criterion_value|
          next if ['Full Score', 'explanation'].include?(criterion_name)

          # 將符合條件的 criterion_name 和 criterion_value 加入到 payload[:record] 中
          payload[:record][criterion_name] = criterion_value
        end
      end
    end

    # 使用 RestClient 发送 POST 请求到 webhook
    begin
      response = RestClient.post(webhook_url, payload.to_json,
                                 { 'X-Webhook-Token': token, content_type: :json, accept: :json })

      # 检查响应
      Rails.logger.error("Webhook call failed: #{response.body}") unless response.code == 201
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error("Webhook call failed: #{e.response}")
    rescue StandardError => e
      Rails.logger.error("Webhook call failed: #{e.message}")
    end
  end

  def test_sentence_builder_example
    ea = essay_assignment
    sbe = SentenceBuilderExampleService.new(ea.general_user_id, ea)
    sbe.generate_examples
  end

  def sentence_builder_for_dify
    sentences = sentence_builder
    vocabs = essay_assignment.vocabs

    sentences.zip(vocabs).map do |sentence_hash, vocab_hash|
      sentence_hash.merge(vocab_hash)
    end
  end

  # def shuffle_questions_and_save
  #   # 解析 news_feed
  #   news_feed_hash = get_news_feed

  #   # 获取问题列表
  #   questions = news_feed_hash["data"]["questions"]

  #   # 打乱问题的顺序
  #   shuffled_questions = questions.shuffle

  #   # 对每个问题的选项内容进行打乱，并更新答案
  #   shuffled_questions.each do |question|
  #     original_answer = question["answer"]
  #     original_options = question["options"]

  #     # 打乱选项内容
  #     shuffled_content = original_options.values.shuffle

  #     # 重新构建选项，保持标签不变
  #     new_options = original_options.keys.zip(shuffled_content).to_h
  #     question["options"] = new_options

  #     # 更新答案
  #     question["answer"] = new_options.key(original_options[original_answer])
  #   end

  #   # 更新 news_feed_hash 中的问题
  #   news_feed_hash["data"]["questions"] = shuffled_questions

  #   # 将打乱后的 news_feed 保存到 transformed_newsfeed
  #   self['meta']['transformed_newsfeed'] = news_feed_hash.to_json
  #   save
  # end

  # def get_transformed_newsfeed
  #   # 检查 transformed_newsfeed 是否存在
  #   if self['meta']['transformed_newsfeed'].present?
  #     # 返回现有的 transformed_newsfeed
  #     JSON.parse(self['meta']['transformed_newsfeed'])
  #   else
  #     # 生成 transformed_newsfeed
  #     shuffle_questions_and_save
  #     JSON.parse(self['meta']['transformed_newsfeed'])
  #   end
  # end

  def build_payload
    payload = {
      record: {
        Id: id,
        User: general_user.nickname,
        Class: general_user.banbie,
        Number: general_user.class_no,
        "Submitted Time": created_at,
        "Time Taken(s)": using_time,
        Status: status
      }
    }

    if category == 'comprehension'
      payload[:record]['Full Score'] = grading.dig('comprehension', 'full_score')
      payload[:record][:Score] = grading.dig('comprehension', 'score')
    else
      grading_data = JSON.parse(grading['data']['text'])
      payload[:record]['Overall Score'] = grading_data['Overall Score']
      payload[:record]['Full Score'] = grading_data['Full Score']
    end

    payload
  end

  # 獲取顯示用的學生信息
  # @return [Hash, nil] 包含用戶信息的哈希，如果無法獲取則返回 nil
  def display_student_info
    return nil unless general_user

    # 構建基本用戶信息
    user_info = {
      id: general_user.id,
      nickname: general_user.nickname,
      email: general_user.email,
      meta: general_user.meta
    }

    # 檢查是否有新的 submission 信息
    if submission_class_name.present? && submission_class_number.present?
      # 使用新的 submission 信息
      user_info.merge!(
        class_name: submission_class_name,
        class_number: submission_class_number,
        school_id: submission_school_id,
        academic_year_id: submission_academic_year_id
      )
    else
      # 向後兼容：使用用戶的備用信息
      user_info.merge!(
        class_name: general_user.banbie,
        class_number: general_user.class_no
      )
    end

    user_info
  end

  private

  # 獲取提交時的學生信息
  # @return [Hash, nil] 包含提交時學生信息的哈希，如果無法獲取則返回 nil
  def submission_student_info
    return nil unless submission_class_name.present? && submission_class_number.present?

    {
      class_name: submission_class_name,
      class_number: submission_class_number,
      school_id: submission_school_id,
      academic_year_id: submission_academic_year_id
    }
  end

  # 獲取當前學生信息
  # @return [Hash, nil] 包含當前學生信息的哈希，如果無法獲取則返回 nil
  def current_student_info
    return nil unless general_user.current_enrollment

    {
      class_name: general_user.current_enrollment.class_name,
      class_number: general_user.current_enrollment.class_number,
      school_id: general_user.current_enrollment.school_academic_year.school_id,
      academic_year_id: general_user.current_enrollment.school_academic_year_id
    }
  end

  # 確保在創建時保存提交時的學生信息
  before_create :save_submission_info

  # 保存提交時的學生信息
  # 如果用戶是教師或沒有入學記錄，使用 banbie 和 class_no 作為備用信息
  def save_submission_info
    Rails.logger.info "Saving submission info for essay grading #{id}"

    # 確保 general_user 存在
    unless general_user
      Rails.logger.error "No general_user found for essay grading #{id}"
      return
    end

    # 獲取當前的入學記錄
    enrollment = general_user.current_enrollment

    if enrollment
      # 獲取學校學年信息
      school_academic_year = enrollment.school_academic_year
      if school_academic_year
        # 如果有完整的入學記錄，保存所有信息
        self.submission_class_name = enrollment.class_name
        self.submission_class_number = general_user.class_no
        self.submission_school_id = school_academic_year.school_id
        self.submission_academic_year_id = school_academic_year.id
        Rails.logger.info "Saved submission info: class_name=#{submission_class_name}, class_no=#{submission_class_number}"
      else
        # 如果沒有學校學年信息，使用備用信息
        Rails.logger.info "No school_academic_year found for enrollment #{enrollment.id}, using fallback info"
        self.submission_class_name = general_user.banbie
        self.submission_class_number = general_user.class_no
        self.submission_school_id = nil
        self.submission_academic_year_id = nil
      end
    else
      # 如果沒有入學記錄，使用備用信息
      Rails.logger.info "No current enrollment found for user #{general_user.id}, using fallback info"
      self.submission_class_name = general_user.banbie
      self.submission_class_number = general_user.class_no
      self.submission_school_id = nil
      self.submission_academic_year_id = nil
    end
  end
end
