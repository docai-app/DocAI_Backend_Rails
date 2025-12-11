# frozen_string_literal: true

# == Schema Information
#
# Table name: schools
#
#  id            :uuid             not null, primary key
#  name          :string           not null
#  code          :string           not null
#  status        :integer          default("active")
#  address       :string
#  contact_email :string
#  contact_phone :string
#  timezone      :string
#  meta          :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_schools_on_code  (code) UNIQUE
#  index_schools_on_name  (name) UNIQUE
#
class School < ApplicationRecord
  # 關聯
  has_many :school_academic_years, dependent: :destroy
  has_many :student_enrollments, through: :school_academic_years
  has_many :teacher_assignments, through: :school_academic_years

  has_many :general_users, through: :student_enrollments
  has_many :general_users, through: :teacher_assignments

  # 附件
  has_one_attached :logo, service: :microsoft

  # 驗證
  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validate :validate_logo_format

  # 學校狀態
  enum status: {
    active: 0,      # 正常運作
    inactive: 1,    # 暫停服務
    pending: 2      # 待啟用
  }

  # 元數據存儲（可擴展的學校特定設置）
  store_accessor :meta,
                 :school_type,           # 學校類型（小學/中學/大學）
                 :curriculum_type,       # 課程類型（本地/國際/IB等）
                 :academic_system,       # 學制（6+3+3/8+4等）
                 :custom_settings        # 自定義設置

  # 獲取當前學年
  def current_academic_year
    school_academic_years.active.first
  end

  # 根據日期獲取學年
  def academic_year_at(date)
    school_academic_years.where('start_date <= ? AND end_date >= ?', date, date).first
  end

  # Scope for eager loading Active Storage attachments
  scope :with_attached_logo, -> { includes(logo_attachment: :blob) }

  # 批量获取所有 logo URLs，避免多次查询 Active Storage
  # 优化：在开发/测试环境直接返回 base_url，避免生成 variant 的开销
  def all_logo_urls
    return {
      logo_url: nil,
      logo_thumbnail_url: nil,
      logo_small_url: nil,
      logo_large_url: nil,
      logo_square_url: nil
    } unless logo.attached?

    # 安全获取 logo URL，处理可能的异常
    base_url = begin
      logo.url
    rescue ArgumentError => e
      # 如果 url 方法需要参数，尝试使用默认方式
      Rails.logger.error("Error getting logo URL: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("Unexpected error getting logo URL: #{e.message}")
      nil
    end

    return {
      logo_url: nil,
      logo_thumbnail_url: nil,
      logo_small_url: nil,
      logo_large_url: nil,
      logo_square_url: nil
    } unless base_url

    # 在开发/测试环境，所有尺寸都返回 base_url，避免生成 variant 的开销
    if Rails.env.development? || Rails.env.test?
      {
        logo_url: base_url,
        logo_thumbnail_url: base_url,
        logo_small_url: base_url,
        logo_large_url: base_url,
        logo_square_url: base_url
      }
    else
      # 生产环境：只生成必要的 variant，使用 rescue 确保即使失败也返回 base_url
      # 优化：使用 memoization 缓存结果，避免重复生成
      @all_logo_urls_cache ||= begin
        {
            logo_url: base_url,
            logo_thumbnail_url: base_url,
            logo_small_url: base_url,
            logo_large_url: base_url,
            logo_square_url: base_url
        #   logo_url: base_url,
        #   logo_thumbnail_url: safe_variant_url(resize_to_limit: [200, 200], fallback: base_url),
        #   logo_small_url: safe_variant_url(resize_to_limit: [100, 100], fallback: base_url),
        #   logo_large_url: safe_variant_url(resize_to_limit: [500, 500], fallback: base_url),
        #   logo_square_url: safe_variant_url(resize_to_fill: [300, 300], fallback: base_url)
        }
      end
    end
  end

  # 返回 logo 的完整 URL
  def logo_url
    logo.attached? ? logo.url : nil
  end

  # 返回縮圖版的 logo URL
  def logo_thumbnail_url
    return nil unless logo.attached?

    if Rails.env.development? || Rails.env.test?
      # 開發和測試環境直接返回原始 URL
      logo.url
    else
      # 生產環境使用變體
      begin
        logo.variant(resize_to_limit: [200, 200])&.processed&.url
      rescue StandardError => e
        Rails.logger.error("處理 logo 縮圖錯誤: #{e.message}")
        logo.url
      end
    end
  end

  # 返回小型版的 logo URL（適用於導航欄）
  def logo_small_url
    return nil unless logo.attached?

    if Rails.env.development? || Rails.env.test?
      logo.url
    else
      begin
        logo.variant(resize_to_limit: [100, 100])&.processed&.url
      rescue StandardError => e
        Rails.logger.error("處理 logo 小圖錯誤: #{e.message}")
        logo.url
      end
    end
  end

  # 返回大型版的 logo URL（適用於首頁）
  def logo_large_url
    return nil unless logo.attached?

    if Rails.env.development? || Rails.env.test?
      logo.url
    else
      begin
        logo.variant(resize_to_limit: [500, 500])&.processed&.url
      rescue StandardError => e
        Rails.logger.error("處理 logo 大圖錯誤: #{e.message}")
        logo.url
      end
    end
  end

  # 返回標準方形的 logo URL（對於需要統一尺寸的地方）
  def logo_square_url
    return nil unless logo.attached?

    if Rails.env.development? || Rails.env.test?
      logo.url
    else
      begin
        logo.variant(resize_to_fill: [300, 300])&.processed&.url
      rescue StandardError => e
        Rails.logger.error("處理 logo 方圖錯誤: #{e.message}")
        logo.url
      end
    end
  end

  private

  # 安全地生成 variant URL，失败时返回 fallback
  def safe_variant_url(options, fallback:)
    begin
      logo.variant(options)&.processed&.url || fallback
    rescue StandardError => e
      Rails.logger.error("處理 logo variant 錯誤: #{e.message}")
      fallback
    end
  end

  # 驗證 logo 格式
  def validate_logo_format
    return unless logo.attached?

    unless logo.content_type.in?(%w[image/png image/jpeg image/jpg image/gif image/webp image/svg+xml])
      errors.add(:logo, '格式無效。允許的格式：PNG, JPEG, JPG, GIF, WEBP, SVG')
    end

    return unless logo.blob.byte_size > 5.megabytes

    errors.add(:logo, '太大了。最大允許大小：5MB')
  end
end
