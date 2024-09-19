# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflow_steps
#
#  id                  :uuid             not null, primary key
#  position            :integer
#  name                :string           not null
#  description         :string
#  user_id             :uuid
#  project_workflow_id :uuid
#  status              :integer          default("pending")
#  is_human            :boolean          default(TRUE)
#  meta                :jsonb
#  dag_meta            :jsonb
#  deadline            :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assignee_id         :uuid
#  user_type           :string           default("User"), not null
#
# Indexes
#
#  index_project_workflow_steps_on_project_workflow_id  (project_workflow_id)
#  index_project_workflow_steps_on_project_workflow_id  (project_workflow_id)
#  index_project_workflow_steps_on_status               (status)
#  index_project_workflow_steps_on_status               (status)
#  index_project_workflow_steps_on_user_id              (user_id)
#  index_project_workflow_steps_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_workflow_id => public.project_workflows.id)
#  fk_rails_...  (project_workflow_id => project_workflows.id)
#  fk_rails_...  (user_id => public.users.id)
#  fk_rails_...  (user_id => users.id)
#
require 'test_helper'

class ProjectWorkflowStepTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
