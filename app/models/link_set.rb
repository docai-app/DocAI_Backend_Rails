# == Schema Information
#
# Table name: link_sets
#
#  id             :bigint(8)        not null, primary key
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  description    :string
#  user_id        :uuid
#  slug           :string
#  request_origin :string
#  workspace      :string
#
# Indexes
#
#  index_link_sets_on_slug       (slug) UNIQUE
#  index_link_sets_on_user_id    (user_id)
#  index_link_sets_on_workspace  (workspace)
#
class LinkSet < ApplicationRecord
  has_many :links, dependent: :destroy
  validates :name, presence: true

  before_create :generate_slug

  def generate_slug
    self.slug ||= generate_unique_slug
  end

  def to_param
    slug
  end

  def generate_unique_slug
    loop do
      slug = SecureRandom.urlsafe_base64(6)
      break slug unless Link.exists?(slug: slug)
    end
  end
end
