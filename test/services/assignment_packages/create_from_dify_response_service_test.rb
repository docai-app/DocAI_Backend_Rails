# frozen_string_literal: true

require 'test_helper'

class AssignmentPackages::CreateFromDifyResponseServiceTest < ActiveSupport::TestCase
  test 'creates assignment package items from supported assignment categories' do
    template = LearningPathTemplate.create!(
      title: 'Travel',
      status: :active,
      prompt_config: {},
      dify_config: {}
    )
    package = AssignmentPackage.create!(
      general_user: general_users(:one),
      learning_path_template: template,
      title: 'Generating',
      status: :generating
    )

    response = {
      'data' => {
        'outputs' => {
          'text' => {
            'title' => 'Travel Practice',
            'description' => 'Practice travel English.',
            'summary' => { 'goal' => 'fluency' },
            'assignments' => [
              {
                'category' => 'talk_lab_speaking',
                'title' => 'Talk about a trip',
                'topic' => 'Travel',
                'assignment' => 'Discuss a past trip.',
                'position' => 10
              },
              {
                'category' => 'not_supported',
                'title' => 'Ignored'
              }
            ]
          }
        }
      }
    }

    AssignmentPackages::CreateFromDifyResponseService.new(
      assignment_package: package,
      dify_response: response
    ).call

    package.reload
    assert package.active?
    assert_equal 'Travel Practice', package.title
    assert_equal 1, package.assignment_package_items.count
    item = package.assignment_package_items.first
    assert item.available?
    assert_equal 1, item.position
    assert_equal 10, item.meta['dify_position']
    assert_equal 'talk_lab_speaking', item.essay_assignment.category
    assert_equal 'assignment_package', item.essay_assignment.meta['source_type']
  end
end
