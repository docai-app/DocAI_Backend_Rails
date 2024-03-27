# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  belongs_to :user, polymorphic: true, optional: true
  belongs_to :entity, optional: true
  has_one :dag, optional: true
end
