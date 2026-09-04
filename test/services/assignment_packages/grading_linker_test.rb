# frozen_string_literal: true

require 'test_helper'

class AssignmentPackages::GradingLinkerTest < ActiveSupport::TestCase
  test 'links draft grading to assignment package item' do
    user = general_users(:one)
    package = AssignmentPackage.create!(general_user: user, title: 'Package', status: :active)
    assignment = user.essay_assignments.create!(
      title: 'First',
      topic: 'First topic',
      assignment: 'First assignment',
      category: 'essay',
      rubric: { 'name' => 'Essay' }
    )
    item = package.assignment_package_items.create!(
      essay_assignment: assignment,
      position: 1,
      status: :available
    )
    grading = assignment.essay_gradings.create!(
      general_user: user,
      topic: assignment.topic,
      essay: 'Draft content',
      status: :draft
    )

    AssignmentPackages::GradingLinker.call(grading)

    assert_equal grading.id, item.reload.essay_grading_id
  end
end
