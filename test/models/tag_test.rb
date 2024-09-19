# frozen_string_literal: true

# == Schema Information
#
# Table name: tags
#
#  id                             :uuid             not null, primary key
#  name                           :string
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  taggings_count                 :integer          default(0)
#  is_checked                     :boolean          default(FALSE)
#  folder_id                      :uuid
#  user_id                        :uuid
#  meta                           :jsonb
#  smart_extraction_schemas_count :integer          default(0)
#
# Indexes
#
#  index_tags_on_name  (name) UNIQUE
#  index_tags_on_name  (name) UNIQUE
#
require 'test_helper'

class TagTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
