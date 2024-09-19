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
# Indexes
#
#  index_folders_on_parent_id  (parent_id)
#  index_folders_on_parent_id  (parent_id)
#  index_folders_on_user_id    (user_id)
#  index_folders_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (user_id => public.users.id)
#
require 'test_helper'

class FolderTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
