# frozen_string_literal: true

require 'test_helper'

class ComprehensionScoreCalculatorTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  def questions(answer)
    Array.new(5) { |i| { 'type' => 'multiple_choice', 'answer' => 'A', 'user_answer' => i == 4 ? 'B' : 'A' } } + [
      { 'type' => 'fill_in_the_blanks', 'blanks' => Array.new(5) { |i| { 'id' => "blank_#{i}", 'answer' => 'word' } }, 'user_answer' => answer }
    ]
  end

  test 'missing empty malformed and primitive answers keep all ten marks' do
    [nil, '', '{}', '[]', 'null', '{bad', false, 0, {}, []].each do |answer|
      result = ComprehensionScoreCalculator.call(questions(answer), fill_in_the_blanks_visible: true)
      assert_equal({ score: 4, full_score: 10, questions_count: 10 }, result)
    end
  end

  test 'disabled blanks are excluded even with saved answers' do
    result = ComprehensionScoreCalculator.call(questions({ 'blank_0' => 'word' }), fill_in_the_blanks_visible: false)
    assert_equal({ score: 4, full_score: 5, questions_count: 5 }, result)
  end

  test 'partial and full answers accept object and string but ignore untrusted IDs' do
    answers = { 'blank_0' => ' WORD ', 'unknown' => 'word' }
    [answers, answers.to_json].each do |value|
      assert_equal 5, ComprehensionScoreCalculator.call(questions(value), fill_in_the_blanks_visible: true)[:score]
    end
    all = (0...5).to_h { |i| ["blank_#{i}", 'word'] }
    q = questions(all)
    q[4]['user_answer'] = 'A'
    original = q.deep_dup
    assert_equal({ score: 10, full_score: 10, questions_count: 10 }, ComprehensionScoreCalculator.call(q, fill_in_the_blanks_visible: true))
    assert_equal original, q
  end

  test 'missing answers do not receive marks for missing answer keys' do
    assert_equal 0, ComprehensionScoreCalculator.call([{ 'type' => 'multiple_choice' }], fill_in_the_blanks_visible: true)[:score]
  end
end
