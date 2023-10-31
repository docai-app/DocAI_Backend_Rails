# frozen_string_literal: true

class UserMailbox < ApplicationRecord
  belongs_to :user
  belongs_to :document
end
