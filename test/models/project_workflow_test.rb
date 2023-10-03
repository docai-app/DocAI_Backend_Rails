# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflows
#
#  id                  :uuid             not null, primary key
#  name                :string           not null
#  status              :integer          default(0), not null
#  description         :string
#  used_id             :uuid
#  is_process_workflow :boolean          default(FALSE)
#  deadline            :datetime
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
require 'test_helper'

class ProjectWorkflowTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
