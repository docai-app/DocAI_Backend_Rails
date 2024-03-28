# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :entity
  has_one :dag

  enum status: { pending: 0, in_progress: 1, finish: 2 }
end
