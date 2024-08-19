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
#  fk_rails_...  (essay_assignment_id => essay_assignments.id)
#  fk_rails_...  (general_user_id => general_users.id)
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
    return essay if essay.present?

    # 下载文件
    audio_data = URI.open(file.url)

    if audio_data
      # 创建临时文件
      temp_audio_file = Tempfile.new(['audio', '.wav'])
      temp_audio_file.binmode
      temp_audio_file.write(audio_data.read)

      # 计算文件大小
      file_size_mb = temp_audio_file.size.to_f / (1024 * 1024)
      puts "File size: #{file_size_mb.round(2)} MB"

      temp_audio_file.rewind

      # 调用 OpenAI 客户端
      response = OpenAIClient.transcribe_audio(temp_audio_file)

      # 清理临时文件
      temp_audio_file.close
      temp_audio_file.unlink

      self['essay'] = response['text']
      save
    else
      puts 'Failed to download audio file.'
      nil
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
