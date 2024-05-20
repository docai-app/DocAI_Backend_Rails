# app/models/link_set.rb
class LinkSet < ApplicationRecord
  has_many :links, dependent: :destroy
  validates :name, presence: true
end