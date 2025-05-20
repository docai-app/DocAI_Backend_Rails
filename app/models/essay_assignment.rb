# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_assignments
#
#  id                   :uuid             not null, primary key
#  topic                :string
#  rubric               :jsonb            not null
#  code                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  assignment           :string
#  number_of_submission :integer          default(0), not null
#  general_user_id      :uuid
#  category             :integer          default("essay"), not null
#  title                :string
#  hints                :string
#  meta                 :jsonb            not null
#  answer_visible       :boolean          default(TRUE), not null
#  remark               :string
#
# Indexes
#
#  index_essay_assignments_on_category         (category)
#  index_essay_assignments_on_code             (code) UNIQUE
#  index_essay_assignments_on_general_user_id  (general_user_id)
#
class EssayAssignment < ApplicationRecord
  store_accessor :rubric, :app_key, :name
  store_accessor :meta, :newsfeed_id, :self_upload_newsfeed, :vocabs, :vocab_examples,
                 :speaking_pronunciation_pass_score, :speaking_pronunciation_sentences, :level

  enum category: %w[essay comprehension speaking_conversation speaking_essay sentence_builder speaking_pronunciation]

  before_create :generate_unique_code
  before_save :normalize_level
  after_save :check_and_generate_vocab_examples
  after_save :check_and_post_speaking_pronunciation_sentences

  has_many :essay_gradings, dependent: :destroy
  belongs_to :general_user

  def get_news_feed
    # 如果 meta 中有 self_upload_newsfeed，直接返回該數據
    return meta['self_upload_newsfeed'] if meta['self_upload_newsfeed'].present?

    # 否則通過 newsfeed_id 請求外部 API
    return nil if meta['newsfeed_id'].nil?

    uri = URI.parse("https://ggform.examhero.com/api/v1/news_feeds/#{newsfeed_id}")
    response = Net::HTTP.get_response(uri)

    return unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def normalize_level
    return unless meta.is_a?(Hash) && meta['level'].present?

    # 定义转换映射
    level_mapping = {
      'level1' => 'CEFR A2',
      'level2' => 'CEFR B2',
      'level3' => 'CEFR C2',
      'Beginner' => 'CEFR A2',
      'Intermediate' => 'CEFR B2',
      'Advanced' => 'CEFR C2'
    }
    # 进行转换
    return unless level_mapping.key?(meta['level'])

    meta['level'] = level_mapping[meta['level']]
  end

  def generate_unique_code
    self.code = loop do
      random_code = SecureRandom.hex(3)
      break random_code unless self.class.exists?(code: random_code)
    end
  end

  def check_and_generate_vocab_examples
    # 只針對 sentence_builder 類型處理
    return unless category == 'sentence_builder'
    # 先確認 meta 有否異動
    return unless saved_change_to_meta?

    # 取得 meta 中 vocabs 的前後值（確保為 Hash 時的操作）
    meta_previous, meta_current = saved_change_to_meta
    previous_vocabs = meta_previous.is_a?(Hash) ? meta_previous['vocabs'] : nil
    current_vocabs  = meta_current.is_a?(Hash) ? meta_current['vocabs'] : nil

    # 檢查 vocabs 是否有改變
    return unless previous_vocabs != current_vocabs

    puts 'running gen examples sidekiq job'
    SentenceBuilderExampleJob.perform_async(id)
  end

  def force_generate_vocab_examples
    return unless category == 'sentence_builder'

    return unless meta[:vocab_examples].nil?

    SentenceBuilderExampleJob.perform_async(id)
  end

  def check_and_post_speaking_pronunciation_sentences
    # 只針對 speaking_pronunciation 類型處理
    return unless category == 'speaking_pronunciation'
    # 先確認 meta 有否異動
    return unless saved_change_to_meta?

    # 取得 meta 中 speaking_pronunciation_sentences 的前後值
    meta_previous, meta_current = saved_change_to_meta
    previous_sentences = meta_previous.is_a?(Hash) ? meta_previous['speaking_pronunciation_sentences'] : nil
    current_sentences = meta_current.is_a?(Hash) ? meta_current['speaking_pronunciation_sentences'] : nil

    # 檢查 speaking_pronunciation_sentences 是否有改變
    return unless previous_sentences != current_sentences

    # 確保 speaking_pronunciation_sentences 格式正確
    return unless current_sentences.is_a?(Array) && current_sentences.all? do |item|
                    item.is_a?(Hash) && item['sentence'].present?
                  end

    # 遍歷每個 sentence 並調用 API
    current_sentences.each do |sentence_obj|
      sentence = sentence_obj['sentence']
      response = Net::HTTP.post(
        URI('https://pronunciation.m2mda.com/pinyin'),
        { language: 'en', sentence: }.to_json,
        'Content-Type' => 'application/json'
      )

      if response.is_a?(Net::HTTPSuccess)
        result = JSON.parse(response.body)
        puts "API Response: #{result}"
        # 更新 sentence_obj 中的字段
        sentence_obj.merge!(result)
      else
        puts "Failed to fetch pronunciation for sentence: #{sentence}"
      end
    end

    # 保存更新后的 meta
    update(meta: meta.merge('speaking_pronunciation_sentences' => current_sentences))
  end
end
