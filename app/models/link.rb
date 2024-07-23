# frozen_string_literal: true

# == Schema Information
#
# Table name: links
#
#  id          :bigint(8)        not null, primary key
#  title       :string
#  url         :string
#  link_set_id :bigint(8)        not null
#  meta        :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  slug        :string
#
# Indexes
#
#  index_links_on_link_set_id  (link_set_id)
#  index_links_on_slug         (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (link_set_id => link_sets.id)
#
class Link < ApplicationRecord
  store_accessor :meta, :is_required_time_limit, :time_limit

  belongs_to :link_set
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :title, presence: true

  before_create :generate_slug

  def to_param
    slug
  end

  def generate_slug
    self.slug ||= generate_unique_slug
  end

  def generate_unique_slug
    loop do
      slug = SecureRandom.urlsafe_base64(6)
      break slug unless Link.exists?(slug:)
    end
  end
end
