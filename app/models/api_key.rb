# frozen_string_literal: true

class ApiKey < ApplicationRecord
  belongs_to :user, optional: true

  before_create :generate_key, :set_expiration

  scope :active, -> { where(active: true) }

  private

  def generate_key
    self.key = SecureRandom.hex(20) # generate random key with length 20
  end

  def set_expiration
    self.expires_at ||= 1.year.from_now # set expiration date to 1 year from now
  end
end
