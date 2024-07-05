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
require 'test_helper'

class LinkTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
