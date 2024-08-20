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
  # store_accessor :rubric, :name
  # store_accessor :rubric, app_key: [:grading, :general_context]
  store_accessor :meta, :newsfeed_id

  enum category: %w[essay comprehension speaking_conversation speaking_essay]

  before_create :generate_unique_code

  has_many :essay_gradings, dependent: :destroy
  belongs_to :general_user

  def get_news_feed
    return nil if self['meta']['newsfeed_id'].nil?

    uri = URI.parse("https://ggform.examhero.com/api/v1/news_feeds/#{newsfeed_id}")
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      nil
    end

  end

  private

  def generate_unique_code
    self.code = loop do
      random_code = SecureRandom.hex(3)
      break random_code unless self.class.exists?(code: random_code)
    end
  end
end
