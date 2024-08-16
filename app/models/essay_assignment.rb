# frozen_string_literal: true

class EssayAssignment < ApplicationRecord
  store_accessor :rubric, :app_key, :name
  # store_accessor :rubric, :name
  # store_accessor :rubric, app_key: [:grading, :general_context]
  store_accessor :meta, :newsfeed_id

  enum category: %w[essay comprehension speaking_conversation speaking_essay]

  before_create :generate_unique_code

  has_many :essay_gradings, dependent: :destroy
  belongs_to :general_user

  private

  def generate_unique_code
    self.code = loop do
      random_code = SecureRandom.hex(3)
      break random_code unless self.class.exists?(code: random_code)
    end
  end
end
