# frozen_string_literal: true

class Membership < ApplicationRecord
  belongs_to :general_user
  belongs_to :group
end
