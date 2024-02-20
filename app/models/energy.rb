# frozen_string_literal: true

# == Schema Information
#
# Table name: public.energies
#
#  id          :uuid             not null, primary key
#  value       :integer          default(100)
#  user_id     :uuid             not null
#  user_type   :string           not null
#  entity_name :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Energy < ApplicationRecord
  belongs_to :user, polymorphic: true
end
