# frozen_string_literal: true

class GeneralUserFile < ApplicationRecord
  resourcify

  belongs_to :general_user
  belongs_to :user_marketplace_item

  validates :file_type, inclusion: { in: %w[pdf png jpg] }
  validates :file_url, presence: true
end
