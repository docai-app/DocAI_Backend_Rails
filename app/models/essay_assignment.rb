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
#
# Indexes
#
#  index_essay_assignments_on_category         (category)
#  index_essay_assignments_on_code             (code) UNIQUE
#  index_essay_assignments_on_general_user_id  (general_user_id)
#
class EssayAssignment < ApplicationRecord
  store_accessor :rubric, :app_key, :name
  store_accessor :meta, :newsfeed_id, :self_upload_newsfeed, :vocabs

  enum category: %w[essay comprehension speaking_conversation speaking_essay sentence_builder]

  before_create :generate_unique_code

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

  private

  def generate_unique_code
    self.code = loop do
      random_code = SecureRandom.hex(3)
      break random_code unless self.class.exists?(code: random_code)
    end
  end
end