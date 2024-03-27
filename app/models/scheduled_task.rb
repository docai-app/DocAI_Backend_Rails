# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  belongs_to :user, polymorphic: true
  has_one :entity
end
