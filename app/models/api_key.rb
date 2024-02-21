# frozen_string_literal: true

# == Schema Information
#
# Table name: public.api_keys
#
#  id          :uuid             not null, primary key
#  user_id     :uuid             not null
#  key         :string           not null
#  expires_at  :datetime
#  active      :boolean          default(TRUE)
#  tenant      :string           not null
#  name        :string
#  description :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_api_keys_on_key      (key) UNIQUE
#  index_api_keys_on_tenant   (tenant)
#  index_api_keys_on_user_id  (user_id)
#
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
