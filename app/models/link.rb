# app/models/link.rb
class Link < ApplicationRecord

  store_accessor :meta, :is_required_time_limit, :time_limit

  belongs_to :link_set
  validates :url, presence: true, format: { with: URI::regexp(%w[http https]) }
  validates :title, presence: true
end