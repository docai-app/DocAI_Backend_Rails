# frozen_string_literal: true

# == Schema Information
#
# Table name: project_tasks
#
#  id           :uuid             not null, primary key
#  title        :string           default("New Project Task"), not null
#  description  :text
#  project_id   :uuid             not null
#  user_id      :uuid             not null
#  is_completed :boolean          default(FALSE), not null
#  order        :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  deadline_at  :datetime
#
# Indexes
#
#  index_project_tasks_on_project_id  (project_id)
#  index_project_tasks_on_project_id  (project_id)
#  index_project_tasks_on_user_id     (user_id)
#  index_project_tasks_on_user_id     (user_id)
#
require 'test_helper'

class ProjectTaskTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
