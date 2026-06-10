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
  include SentencePuzzleSupport

  store_accessor :rubric, :app_key, :name
  store_accessor :meta, :newsfeed_id, :self_upload_newsfeed, :vocabs, :vocab_examples,
                 :speaking_pronunciation_pass_score, :speaking_pronunciation_sentences, :level, :sample_essay,
                 :listening

  REVISED_ESSAY_WORKFLOW_MAP = {
    'opinion_agree_disagree' => 'app-7504Yy549InHGsKstZgRNjgk',
    'discuss_both_views' => 'app-zEjN5PjYVQLKQcmDFGGAOXZC',
    'outweigh_questions' => 'app-zEjN5PjYVQLKQcmDFGGAOXZC',
    'discussion_plus_opinion' => 'app-zEjN5PjYVQLKQcmDFGGAOXZC',
    'causes_essay' => 'app-x5AG2tZufeO2yT0rIYSPZxlP',
    'effects_essay' => 'app-x5AG2tZufeO2yT0rIYSPZxlP',
    'problems_essay' => 'app-x5AG2tZufeO2yT0rIYSPZxlP',
    'causes_and_effects_essay' => 'app-2Hkxl2VawFTiAOyQUdmoqodE',
    'solutions_essay' => 'app-2Hkxl2VawFTiAOyQUdmoqodE',
    'problems_and_solutions_essay' => 'app-2Hkxl2VawFTiAOyQUdmoqodE',
    'compare_and_contrast_essay' => 'app-EBDukshGNAM6yzaNoN8God3w',
    'descriptive_essay' => 'app-Sx65owgHtosF35QOsjToIM7y',
    'narrative_essay' => 'app-uQUCNy9WxiVE2tapyUgmQkkz'
  }.freeze

  ESSAY_TYPE_LABELS = {
    'opinion_agree_disagree' => 'Opinion (Agree/Disagree)',
    'discuss_both_views' => 'Discuss Both Views (Balanced Discussion)',
    'outweigh_questions' => 'Outweigh Questions (Argumentative)',
    'discussion_plus_opinion' => 'Discussion Plus Opinion (Personal Position)',
    'causes_essay' => 'Causes Essay',
    'effects_essay' => 'Effects Essay',
    'problems_essay' => 'Problems Essay',
    'causes_and_effects_essay' => 'Causes and Effects Essay',
    'solutions_essay' => 'Solutions Essay',
    'problems_and_solutions_essay' => 'Problems and Solutions Essay',
    'compare_and_contrast_essay' => 'Compare and Contrast Essay',
    'descriptive_essay' => 'Descriptive Essay',
    'narrative_essay' => 'Narrative Essay'
  }.freeze

  SPEAKING_PRONUNCIATION_MODEL_AUDIO_FIELD_KEYS = %w[
    model_audio_url
    model_audio_status
    model_tts_provider
    model_tts_voice
    model_tts_generated_at
    model_audio_playback_rate
  ].freeze

  SPEAKING_PRONUNCIATION_LIST_META_EXCLUDE_KEY = 'speaking_pronunciation_sentences'

  def self.meta_for_list_response(meta)
    return meta unless meta.is_a?(Hash)

    meta.except(SPEAKING_PRONUNCIATION_LIST_META_EXCLUDE_KEY)
  end

  def self.list_meta_sql_select
    "essay_assignments.meta - '#{SPEAKING_PRONUNCIATION_LIST_META_EXCLUDE_KEY}' AS meta"
  end

  def as_list_json
    json = as_json
    json['meta'] = self.class.meta_for_list_response(json['meta'])
    json
  end

  ESSAY_TYPE_LABELS_WITH_NUMBER = {
    'opinion_agree_disagree' => 'Essay Type 1: Opinion (Agree/Disagree)',
    'discuss_both_views' => 'Essay Type 2: Discuss Both Views (Balanced Discussion)',
    'outweigh_questions' => 'Essay Type 3: Outweigh Questions (Argumentative)',
    'discussion_plus_opinion' => 'Essay Type 4: Discussion Plus Opinion (Personal Position)',
    'causes_essay' => 'Essay Type 5: Causes Essay',
    'effects_essay' => 'Essay Type 6: Effects Essay',
    'problems_essay' => 'Essay Type 7: Problems Essay',
    'causes_and_effects_essay' => 'Essay Type 8: Causes and Effects Essay',
    'solutions_essay' => 'Essay Type 9: Solutions Essay',
    'problems_and_solutions_essay' => 'Essay Type 10: Problems and Solutions Essay',
    'compare_and_contrast_essay' => 'Essay Type 11: Compare and Contrast Essay',
    'descriptive_essay' => 'Essay Type: Descriptive Essay',
    'narrative_essay' => 'Essay Type: Narrative Essay'
  }.freeze

  enum category: %w[essay comprehension speaking_conversation speaking_essay sentence_builder speaking_pronunciation listening sentence_puzzle]

  before_create :generate_unique_code
  before_validation :assign_default_sentence_puzzle_rubric
  before_save :normalize_level
  after_save :check_and_generate_vocab_examples
  after_save :persist_speaking_conversation_question_audios
  after_commit :enqueue_speaking_pronunciation_post_process_job, on: %i[create update]

  has_many :essay_gradings, dependent: :destroy
  belongs_to :general_user
  belongs_to :community, optional: true

  # 作業分配關聯
  has_many :assignment_distributions, dependent: :destroy
  has_many :assignment_student_assignments, dependent: :destroy
  has_many :assigned_students, through: :assignment_student_assignments, source: :general_user

  # 補充練習記錄關聯
  has_many :supplement_practice_records, dependent: :destroy

  # 檔案附件 - 為IELTS看圖作文添加圖片上傳功能
  has_one_attached :graph_image, service: :microsoft

  # 驗證
  validates :topic, presence: true
  validates :assignment, presence: true
  validates :category, presence: true
  validates :title, presence: true
  validates :rubric, presence: true
  validate :validate_sentence_puzzle_configuration, if: -> { category == 'sentence_puzzle' }

  # IELTS看圖作文的圖片格式驗證
  validates :graph_image, content_type: { in: ['image/jpeg'],
                                          message: 'must be a JPEG image' },
                          size: { less_than: 10.megabytes,
                                  message: 'must be less than 10MB' },
                          allow_blank: true

  # 將 essay_gradings 中的 app_key 重新獲取一次
  # @essay_grading.grading['app_key'] = @essay_assignment.rubric['app_key']['grading']
  # @essay_grading.general_context['app_key'] = @essay_assignment.rubric['app_key']['general_context']
  def update_essay_gradings_app_key
    essay_gradings.each do |essay_grading|
      essay_grading.grading['app_key'] = rubric['app_key']['grading']
      essay_grading.general_context['app_key'] = rubric['app_key']['general_context']
      essay_grading.save!
    end
  end

  # 返回圖片的完整URL - 參考School模型的logo_url實現
  def graph_image_url
    return nil unless graph_image.attached?

    begin
      graph_image.url
    rescue StandardError => e
      Rails.logger.error "[EssayAssignment#graph_image_url] Failed to generate URL for assignment #{id}: #{e.message}"
      nil
    end
  end

  def get_news_feed
    # 如果 meta 中有 self_upload_newsfeed，直接返回該數據
    return meta['self_upload_newsfeed'] if meta['self_upload_newsfeed'].present?

    # 否則通過 newsfeed_id 請求外部 API
    return nil if meta['newsfeed_id'].nil?

    uri = URI.parse("https://ggform.examhero.com/api/v1/news_feeds/#{newsfeed_id}/form.json")

    # 检查 essay_assignment 和 meta.level 是否存在
    if meta&.key?('level') && meta['level'].present?
      query_params = URI.decode_www_form(uri.query || '').to_h
      query_params['level'] = meta['level']
      uri.query = URI.encode_www_form(query_params)
    end

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

  def revised_essay_workflow_app_key
    env_key = REVISED_ESSAY_WORKFLOW_MAP[essay_type]
    # puts "revised_essay_workflow_app_key: #{env_key} #{essay_type}"
    return nil if env_key.blank?

    env_key
  end

  def revised_essay_type_label
    ESSAY_TYPE_LABELS[essay_type].presence || essay_type.to_s.humanize
  end

  def revised_essay_type_label_with_number
    ESSAY_TYPE_LABELS_WITH_NUMBER[essay_type].presence || essay_type.to_s.humanize
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

  def enqueue_speaking_pronunciation_post_process_job
    return unless speaking_pronunciation?
    return unless valid_speaking_pronunciation_sentences?

    pending_audio = speaking_pronunciation_has_pending_model_audio?
    sentences_changed = speaking_pronunciation_sentences_changed_in_last_commit?
    return unless pending_audio || sentences_changed

    SpeakingPronunciationPostProcessJob.perform_async(id, sentences_changed)
  end

  def speaking_pronunciation_post_process_needed?
    speaking_pronunciation_has_pending_model_audio? ||
      speaking_pronunciation_sentences_changed_in_last_commit?
  end

  def speaking_pronunciation_sentences_changed_in_last_commit?
    return false unless previous_changes.key?('meta')

    meta_previous, meta_current = previous_changes['meta']
    speaking_pronunciation_sentences_meaningfully_changed?(meta_previous, meta_current)
  end

  def speaking_pronunciation_sentences_meaningfully_changed?(meta_previous, meta_current)
    previous = normalized_sentences_for_post_process_compare(
      meta_previous.is_a?(Hash) ? meta_previous['speaking_pronunciation_sentences'] : nil
    )
    current = normalized_sentences_for_post_process_compare(
      meta_current.is_a?(Hash) ? meta_current['speaking_pronunciation_sentences'] : nil
    )
    previous != current
  end

  def normalized_sentences_for_post_process_compare(sentences)
    Array(sentences).filter_map do |item|
      next unless item.is_a?(Hash)

      normalized = item.deep_stringify_keys
      sentence = normalized['sentence'].to_s.strip
      next if sentence.blank?

      {
        'sentence' => sentence,
        'model_audio_url' => normalized['model_audio_url']
      }
    end
  end

  def valid_speaking_pronunciation_sentences?
    sentences = speaking_pronunciation_sentences_from_meta
    sentences.is_a?(Array) && sentences.all? do |item|
      item.is_a?(Hash) && item.with_indifferent_access[:sentence].present?
    end
  end

  def speaking_pronunciation_has_pending_model_audio?
    Array(speaking_pronunciation_sentences_from_meta).any? do |sentence|
      speaking_pronunciation_model_audio_data_url?(sentence)
    end
  end

  def run_speaking_pronunciation_post_process!(run_pinyin: true)
    return unless speaking_pronunciation?
    return unless valid_speaking_pronunciation_sentences?

    persist_speaking_pronunciation_model_audios! if speaking_pronunciation_has_pending_model_audio?
    enrich_speaking_pronunciation_pinyin! if run_pinyin
  end

  def enrich_speaking_pronunciation_pinyin!
    return unless speaking_pronunciation?

    reload if persisted?

    sentences = speaking_pronunciation_sentences_from_meta
    return unless sentences.is_a?(Array) && sentences.all? do |item|
      item.is_a?(Hash) && item.with_indifferent_access[:sentence].present?
    end

    enriched = false
    normalized_sentences = sentences.map do |sentence_obj|
      sentence = sentence_obj.with_indifferent_access[:sentence]
      normalized = sentence_obj.deep_stringify_keys
      preserved_model_audio = normalized.slice(*SPEAKING_PRONUNCIATION_MODEL_AUDIO_FIELD_KEYS)

      begin
        response = Net::HTTP.post(
          URI('https://pronunciation.m2mda.com/pinyin'),
          { language: 'en', sentence: }.to_json,
          'Content-Type' => 'application/json'
        )

        if response.is_a?(Net::HTTPSuccess) && response.body.present?
          result = JSON.parse(response.body)
          if result.is_a?(Hash) && result.present?
            Rails.logger.info("[EssayAssignment#enrich_speaking_pronunciation_pinyin!] Pinyin API response for sentence: #{sentence}")
            pronunciation_fields = result.except('sentence', *SPEAKING_PRONUNCIATION_MODEL_AUDIO_FIELD_KEYS)
            normalized.merge!(pronunciation_fields)
            enriched = true
          else
            Rails.logger.warn("[EssayAssignment#enrich_speaking_pronunciation_pinyin!] Empty pinyin response for sentence: #{sentence}")
          end
        else
          Rails.logger.warn("[EssayAssignment#enrich_speaking_pronunciation_pinyin!] Failed to fetch pronunciation for sentence: #{sentence}")
        end
      rescue StandardError => e
        Rails.logger.error("[EssayAssignment#enrich_speaking_pronunciation_pinyin!] Pinyin API error for sentence '#{sentence}': #{e.message}")
      end

      normalized.merge!(preserved_model_audio)
      normalized
    end

    return unless enriched

    updated_meta = (read_attribute(:meta) || {}).deep_dup
    updated_meta['speaking_pronunciation_sentences'] = normalized_sentences
    update_column(:meta, updated_meta)
  end

  def persist_speaking_conversation_question_audios
    return unless category == 'speaking_conversation'
    return unless saved_change_to_meta?

    speaking_conversation = meta.is_a?(Hash) ? meta['speaking_conversation'] : nil
    return unless speaking_conversation.is_a?(Hash)
    return unless speaking_conversation['mode'] == 'preset_questions'

    questions = speaking_conversation['questions']
    return unless questions.is_a?(Array)

    changed = false
    normalized_questions = questions.each_with_index.map do |question, index|
      next question unless question.is_a?(Hash)

      normalized = question.deep_stringify_keys
      audio_url = normalized['audio_url']
      next normalized unless audio_url.is_a?(String) && audio_url.start_with?('data:')

      question_id = normalized['id'].presence || "q_#{index + 1}"
      persisted_url = SpeakingConversationAudioStorageService.persist_data_url!(
        audio_url,
        filename_prefix: "speaking_conversation/assignments/#{id}/#{question_id}"
      )

      if persisted_url.present? && persisted_url != audio_url
        normalized['audio_url'] = persisted_url
        changed = true
      end

      normalized
    end

    return unless changed

    updated_meta = meta.deep_dup
    updated_meta['speaking_conversation'] = speaking_conversation.merge('questions' => normalized_questions)
    update_column(:meta, updated_meta)
  end

  def persist_speaking_pronunciation_model_audios!
    return unless speaking_pronunciation?

    reload if persisted?

    sentences = speaking_pronunciation_sentences_from_meta
    return unless sentences.is_a?(Array)
    return unless sentences.any? { |sentence| speaking_pronunciation_model_audio_data_url?(sentence) }

    changed = false
    normalized_sentences = sentences.each_with_index.map do |sentence, index|
      next sentence unless sentence.is_a?(Hash)

      normalized = sentence.deep_stringify_keys
      audio_url = normalized['model_audio_url']
      unless speaking_pronunciation_model_audio_data_url?(normalized)
        next normalized
      end

      sentence_key = normalized['id'].presence || "sentence_#{index + 1}"
      persisted_url = SpeakingConversationAudioStorageService.persist_data_url!(
        audio_url,
        filename_prefix: "speaking_pronunciation/assignments/#{id}/#{sentence_key}"
      )

      if persisted_url.present? && persisted_url != audio_url
        normalized['model_audio_url'] = persisted_url
        changed = true
      else
        Rails.logger.warn(
          "[EssayAssignment#persist_speaking_pronunciation_model_audios!] Failed to persist model audio for assignment #{id}, sentence #{sentence_key}"
        )
      end

      normalized
    end

    return unless changed

    updated_meta = (read_attribute(:meta) || {}).deep_dup
    updated_meta['speaking_pronunciation_sentences'] = normalized_sentences
    update_column(:meta, updated_meta)
  end

  def speaking_pronunciation_sentences_from_meta
    raw_meta = read_attribute(:meta)
    if raw_meta.is_a?(Hash)
      indifferent_meta = raw_meta.with_indifferent_access
      return indifferent_meta[:speaking_pronunciation_sentences] if indifferent_meta[:speaking_pronunciation_sentences].present?
    end

    speaking_pronunciation_sentences
  end

  def speaking_pronunciation_model_audio_data_url?(sentence)
    return false unless sentence.is_a?(Hash)

    sentence.with_indifferent_access[:model_audio_url].to_s.start_with?('data:')
  end

  # 作業分配相關方法
  def distributed?
    assignment_distributions.active.exists?
  end

  def assigned_to_student?(student)
    assignment_student_assignments.where(general_user: student).exists?
  end

  # 獲取所有被分配的學生（去重）
  def all_assigned_students
    GeneralUser.where(id: assignment_student_assignments.select(:general_user_id).distinct)
  end

  # 獲取作業統計
  def assignment_statistics
    total = assignment_student_assignments.count
    completed = assignment_student_assignments.completed.count
    pending = assignment_student_assignments.assigned.count
    overdue = assignment_student_assignments.overdue.count
    
    {
      total: total,
      completed: completed,
      pending: pending,
      overdue: overdue,
      completion_rate: total.zero? ? 0.0 : (completed.to_f / total * 100).round(2)
    }
  end
end
