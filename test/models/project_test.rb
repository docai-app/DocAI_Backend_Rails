# frozen_string_literal: true

# == Schema Information
#
# Table name: projects
#
#  id          :uuid             not null, primary key
#  name        :string           default("New Project"), not null
#  description :string
#  user_id     :uuid             not null
#  folder_id   :uuid             not null
#  is_public   :boolean          default(FALSE)
#  is_finished :boolean          default(FALSE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  deadline_at :datetime
#
# Foreign Keys
#
#  fk_rails_...  (folder_id => public.folders.id)
#  fk_rails_...  (folder_id => folders.id)
#  fk_rails_...  (user_id => public.users.id)
#  fk_rails_...  (user_id => users.id)
#
require 'test_helper'

class ProjectTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
