# frozen_string_literal: true

class EnergyConsumptionRecord < ApplicationRecord
  belongs_to :user, polymorphic: true
end
