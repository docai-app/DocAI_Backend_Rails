# frozen_string_literal: true

# == Schema Information
#
# Table name: public.community_memberships
#
#  id              :uuid             not null, primary key
#  community_id    :uuid             not null
#  general_user_id :uuid             not null
#  meta            :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_community_memberships_on_community_and_user  (community_id,general_user_id) UNIQUE
#  index_community_memberships_on_community_id        (community_id)
#  index_community_memberships_on_general_user_id     (general_user_id)
#
class CommunityMembership < ApplicationRecord
  # 关联关系
  belongs_to :community
  belongs_to :general_user

  # 验证
  validates :community_id, uniqueness: { scope: :general_user_id, 
                                         message: 'User is already a member of this community' }
  validates :meta, presence: true

  # Meta字段访问器
  store_accessor :meta, :joined_at, :role

  # 回调
  before_create :set_joined_at

  # 角色定义
  ROLES = %w[member moderator].freeze

  # 验证角色
  validates :role, inclusion: { in: ROLES }, allow_blank: true

  # 设置默认角色
  after_initialize :set_default_role

  # 检查是否为版主
  def moderator?
    role == 'moderator'
  end

  # 检查是否为普通成员
  def member?
    role == 'member' || role.blank?
  end

  private

  def set_joined_at
    self.joined_at = Time.current if joined_at.blank?
  end

  def set_default_role
    self.role = 'member' if role.blank?
  end
end