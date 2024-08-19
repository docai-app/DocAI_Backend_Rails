# frozen_string_literal: true

# == Schema Information
#
# Table name: public.memberships
#
#  id              :uuid             not null, primary key
#  general_user_id :uuid             not null
#  group_id        :uuid             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (group_id => groups.id)
#
class Membership < ApplicationRecord
  belongs_to :general_user
  belongs_to :group
end
