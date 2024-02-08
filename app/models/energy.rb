# frozen_string_literal: true

class Energy < ApplicationRecord
  belongs_to :user, polymorphic: true
end
