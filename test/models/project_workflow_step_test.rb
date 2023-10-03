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
#  assignee_id         :integer
#  project_workflow_id :uuid             not null
#  status              :integer          default(0)
#  is_human            :boolean          default(TRUE)
#  meta                :jsonb
#  dag_meta            :jsonb
#  deadline            :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
require 'test_helper'

class ProjectWorkflowStepTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
