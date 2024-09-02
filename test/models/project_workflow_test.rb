# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflows
#
#  id                  :uuid             not null, primary key
#  name                :string           not null
#  status              :integer          default("draft"), not null
#  description         :string
#  user_id             :uuid
#  is_process_workflow :boolean          default(FALSE)
#  deadline            :datetime
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  folder_id           :uuid
#  is_template         :boolean          default(FALSE), not null
#  source_workflow_id  :uuid
#  user_type           :string           default("User"), not null
#
# Indexes
#
#  index_project_workflows_on_folder_id            (folder_id)
#  index_project_workflows_on_folder_id            (folder_id)
#  index_project_workflows_on_is_process_workflow  (is_process_workflow)
#  index_project_workflows_on_is_process_workflow  (is_process_workflow)
#  index_project_workflows_on_source_workflow_id   (source_workflow_id)
#  index_project_workflows_on_source_workflow_id   (source_workflow_id)
#  index_project_workflows_on_status               (status)
#  index_project_workflows_on_status               (status)
#
# Foreign Keys
#
#  fk_rails_...  (folder_id => folders.id)
#  fk_rails_...  (folder_id => public.folders.id)
#
require 'test_helper'

class ProjectWorkflowTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
