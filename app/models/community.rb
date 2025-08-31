# frozen_string_literal: true

# == Schema Information
#
# Table name: public.communities
#
#  id              :uuid             not null, primary key
#  name            :string           not null
#  description     :text
#  meta            :jsonb            default: {}
#  general_user_id :uuid             not null
#  code            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_communities_on_code             (code) UNIQUE
#  index_communities_on_general_user_id  (general_user_id)
#
class Community < ApplicationRecord
  # Meta字段访问器 - 为未来扩展预留空间
  store_accessor :meta, :community_type, :settings, :features, :permissions, :custom_fields
  
  # 关联关系
  belongs_to :general_user  # 创建者
  has_many :community_memberships, dependent: :destroy
  has_many :members, through: :community_memberships, source: :general_user
  has_many :essay_assignments, dependent: :nullify

  # 文件附件 - Community 封面图
  has_one_attached :cover, service: :microsoft

  # 验证
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :code, presence: true, uniqueness: true, length: { is: 6 }

  # 回调
  before_validation :generate_unique_code, on: :create
  before_validation :normalize_code

  # 封面图片验证
  validates :cover, content_type: { in: ['image/jpeg', 'image/png', 'image/jpg'],
                                   message: 'must be a JPEG or PNG image' },
                   size: { less_than: 5.megabytes,
                          message: 'must be less than 5MB' },
                   allow_blank: true

  # 返回封面图片的完整URL
  def cover_url
    return nil unless cover.attached?

    begin
      cover.url
    rescue StandardError => e
      Rails.logger.error "[Community#cover_url] Failed to generate URL for community #{id}: #{e.message}"
      nil
    end
  end

  # 获取成员数量
  def members_count
    community_memberships.count
  end

  # 获取作业数量
  def essay_assignments_count
    essay_assignments.count
  end

  # 检查用户是否为创建者
  def creator?(user)
    general_user_id == user.id
  end

  # 检查用户是否为成员
  def member?(user)
    community_memberships.exists?(general_user: user)
  end

  # 添加成员
  def add_member(user)
    return false if member?(user)

    community_memberships.create(general_user: user)
  rescue ActiveRecord::RecordInvalid
    false
  end

  # 移除成员
  def remove_member(user)
    community_memberships.where(general_user: user).destroy_all
  end

  # 获取统计信息
  def stats
    {
      members_count: members_count,
      essay_assignments_count: essay_assignments_count,
      created_at: created_at
    }
  end

  # 通过code查找Community
  def self.find_by_code(code)
    find_by(code: code&.upcase)
  end

  private

  # 生成唯一的6位验证码
  def generate_unique_code
    return if code.present?

    self.code = loop do
      random_code = SecureRandom.alphanumeric(6).upcase
      break random_code unless self.class.exists?(code: random_code)
    end
  end

  # 标准化code为大写
  def normalize_code
    self.code = code&.upcase if code.present?
  end
end