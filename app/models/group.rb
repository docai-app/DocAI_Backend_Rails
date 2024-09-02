# frozen_string_literal: true

# == Schema Information
#
# Table name: public.groups
#
#  name       :string           not null
#  owner_id   :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  id         :uuid             not null, primary key
#
# Foreign Keys
#
#  groups_owner_id_fkey  (owner_id => public.general_users.id)
#
class Group < ApplicationRecord
  belongs_to :owner, class_name: 'GeneralUser', foreign_key: 'owner_id'

  # 設置多對多關聯
  has_many :memberships, dependent: :destroy
  has_many :general_users, through: :memberships
end
