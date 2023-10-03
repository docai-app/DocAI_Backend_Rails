# frozen_string_literal: true

# == Schema Information
#
# Table name: folders
#
#  id         :uuid             not null, primary key
#  name       :string           default("New Folder"), not null
#  parent_id  :uuid
#  user_id    :uuid
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'test_helper'

class FolderTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
