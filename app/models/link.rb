# app/models/link.rb
class Link < ApplicationRecord
  belongs_to :link_set
  validates :url, presence: true, format: { with: URI::regexp(%w[http https]) }
  validates :title, presence: true
end