# frozen_string_literal: true

class GeneralUserFeed < ApplicationRecord
  belongs_to :general_user
  belongs_to :user_marketplace_item

  validates :file_url, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[file_type]
  end
end
