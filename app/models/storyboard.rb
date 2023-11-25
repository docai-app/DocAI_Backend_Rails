# frozen_string_literal: true

class Storyboard < ApplicationRecord
  has_many :storyboard_item_associations, dependent: :destroy
  has_many :items, through: :storyboard_item_associations
  belongs_to :user
end
