# frozen_string_literal: true

require 'test_helper'

class AssignmentPackages::ProgressUpdaterTest < ActiveSupport::TestCase
  test 'marks current item completed and unlocks next item for non draft grading' do
    user = general_users(:one)
    package = AssignmentPackage.create!(general_user: user, title: 'Package', status: :active)
    first_assignment = user.essay_assignments.create!(
      title: 'First',
      topic: 'First topic',
      assignment: 'First assignment',
      category: 'essay',
      rubric: { 'name' => 'Essay' }
    )
    second_assignment = user.essay_assignments.create!(
      title: 'Second',
      topic: 'Second topic',
      assignment: 'Second assignment',
      category: 'essay',
      rubric: { 'name' => 'Essay' }
    )
    first_item = package.assignment_package_items.create!(
      essay_assignment: first_assignment,
      position: 1,
      status: :available
    )
    second_item = package.assignment_package_items.create!(
      essay_assignment: second_assignment,
      position: 2,
      status: :locked
    )
    grading = first_assignment.essay_gradings.create!(
      general_user: user,
      topic: first_assignment.topic,
      essay: 'Submitted',
      status: :pending
    )

    AssignmentPackages::ProgressUpdater.call(grading)

    assert first_item.reload.completed?
    assert_equal grading.id, first_item.essay_grading_id
    assert second_item.reload.available?
    assert_equal 2, package.reload.progress['total_items']
    assert_equal 1, package.progress['completed_items']
  end
end
