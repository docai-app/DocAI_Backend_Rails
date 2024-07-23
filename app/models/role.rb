# frozen_string_literal: true

# == Schema Information
#
# Table name: roles
#
#  id            :uuid             not null, primary key
#  name          :string
#  resource_type :string
#  resource_id   :uuid
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_roles_on_name_and_resource_type_and_resource_id  (name,resource_type,resource_id)
#  index_roles_on_resource                                (resource_type,resource_id)
#
class Role < ApplicationRecord
  has_and_belongs_to_many :users, join_table: :users_roles
  # has_and_belongs_to_many :general_users, join_table: :general_users_roles
  has_and_belongs_to_many :general_users, join_table: :general_users_roles, foreign_key: :general_user_id,
                                          association_foreign_key: :role_id

  belongs_to :resource,
             polymorphic: true,
             optional: true

  validates :resource_type,
            inclusion: { in: Rolify.resource_types },
            allow_nil: true

  scopify
end
