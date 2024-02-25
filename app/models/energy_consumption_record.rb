# frozen_string_literal: true

# == Schema Information
#
# Table name: public.energy_consumption_records
#
#  id                  :uuid             not null, primary key
#  marketplace_item_id :uuid             not null
#  energy_consumed     :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  user_type           :string           not null
#  user_id             :uuid             not null
#
class EnergyConsumptionRecord < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :marketplace_item, dependent: :destroy, foreign_key: :marketplace_item_id
end
