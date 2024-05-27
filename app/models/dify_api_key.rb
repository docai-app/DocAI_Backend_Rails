class DifyApiKey < ApplicationRecord
  before_validation :generate_api_key, on: :create

  validates :domain, presence: true
  validates :workspace, presence: true
  validates :api_key, presence: true
  validates_uniqueness_of :domain, scope: :workspace

  # 啟用 API 密鑰
  def activate!
    update(actived_at: Time.current)
  end

  # 停用 API 密鑰
  def deactivate!
    update(actived_at: nil)
  end

  # 判斷 API 密鑰是否啟用
  def active?
    actived_at.present?
  end

  private

  def generate_api_key
    self.api_key = SecureRandom.hex(20) if self.api_key.blank?
  end
end