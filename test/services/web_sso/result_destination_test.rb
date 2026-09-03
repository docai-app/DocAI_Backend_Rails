# frozen_string_literal: true

require 'test_helper'

class WebSsoResultDestinationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  Assignment = Struct.new(:category)
  Grading = Struct.new(:id, :status, :essay_assignment, :newsfeed_id)

  test 'uses the shared grading result for standard student assignments' do
    grading = Grading.new('grading-1', 'graded', Assignment.new('speaking_pronunciation'), nil)

    assert_equal '/essay/grading/grading-1', WebSso::ResultDestination.path_for(grading)
  end

  test 'uses the existing comprehension result and safely encodes newsfeed id' do
    grading = Grading.new('grading-2', 'graded', Assignment.new('comprehension'), 'feed value/1')

    assert_equal(
      '/comprehension/show/grading-2?newsfeed_id=feed+value%2F1',
      WebSso::ResultDestination.path_for(grading)
    )
  end

  test 'does not open draft or unsupported assignment results' do
    draft = Grading.new('grading-3', 'draft', Assignment.new('essay'), nil)
    listening = Grading.new('grading-4', 'graded', Assignment.new('listening'), nil)

    assert_raises(WebSso::ResultDestination::ResultNotAvailableError) do
      WebSso::ResultDestination.path_for(draft)
    end
    assert_raises(WebSso::ResultDestination::ResultNotAvailableError) do
      WebSso::ResultDestination.path_for(listening)
    end
  end
end
