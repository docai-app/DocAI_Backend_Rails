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
#
require 'test_helper'

class ProjectWorkflowTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
