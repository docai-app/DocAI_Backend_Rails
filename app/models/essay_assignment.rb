class EssayAssignment < ApplicationRecord

  store_accessor :rubric, :app_key, :name

  before_create :generate_unique_code

  has_many :essay_gradings, dependent: :destroy

  private

  def generate_unique_code
    self.code = loop do
      random_code = SecureRandom.hex(3)
      break random_code unless self.class.exists?(code: random_code)
    end
  end
end
