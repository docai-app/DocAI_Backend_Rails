# frozen_string_literal: true

require 'test_helper'

class EssayFeedbackValidatorTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  def feedback
    { 'Overall Score' => 7, 'Full Score' => 9,
      'Criterion 1' => { 'Grammar' => 7, 'Full Score' => 9, 'explanation' => 'Use goes.' },
      'Sentence1' => { 'sentence' => 'She goes.', 'errors' => {} } }
  end

  test 'normal zero score object and fenced responses with genuinely no errors are valid' do
    data = feedback
    data['Overall Score'] = 0
    [data, data.to_json, "`#{data.to_json}`", "```json\n#{data.to_json}\n```"].each do |text|
      assert EssayFeedbackValidator.validate!({ 'text' => text }, stage: 'grading', category: 'essay')
    end
  end

  test 'missing criteria scores grammar and malformed output are rejected' do
    ['Overall Score', 'Full Score', 'Criterion 1', 'Sentence1'].each do |key|
      assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => feedback.except(key) }, stage: 'grading', category: 'essay') }
    end
    [nil, '', {}, { 'text' => '{}' }, { 'text' => 'null' }].each do |output|
      assert_raises(ArgumentError, JSON::ParserError) { EssayFeedbackValidator.validate!(output, stage: 'grading', category: 'essay') }
    end
  end

  test 'nonfinite negative out of range and zero denominator never pass' do
    [['Overall Score', -1], ['Overall Score', 10], ['Overall Score', Float::NAN], ['Full Score', 0], ['Full Score', 'unknown']].each do |key, value|
      assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => feedback.merge(key => value) }, stage: 'grading', category: 'essay') }
    end
    data = feedback
    data['Criterion 1']['Grammar'] = nil
    assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => data }, stage: 'grading', category: 'essay') }
  end

  test 'broken grammar explanation and empty general context or revised essay fail' do
    data = feedback
    data['Sentence1']['errors'] = { 'error1' => { 'word' => 'go' } }
    assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => data }, stage: 'grading', category: 'essay') }
    ['general_context', 'revised_essay'].each do |stage|
      assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => '' }, stage: stage, category: 'essay') }
    end
    assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => '{}' }, stage: 'general_context', category: 'essay') }
    assert EssayFeedbackValidator.validate!({ 'text' => 'Good work.' }, stage: 'general_context', category: 'essay')
  end

  test 'supplement answer keys options types and duplicate IDs are validated before readiness' do
    base = { 'sections' => [{ 'topic' => 'Verbs', 'type' => 'multiple_choice', 'questions' => [{ 'question' => 'I __.', 'options' => ['am', 'is'], 'answer' => 'am' }] }] }
    parse = ->(data) { SupplementPracticeParserService.new(Struct.new(:grading).new({ 'supplement_practice' => { 'text' => data } })).parse }
    assert parse.call(base)
    [{ 'answer' => 'are' }, { 'options' => ['am', 'am'] }, { 'options' => ['am', ''] }, { 'question' => '' }].each do |change|
      data = base.deep_dup
      data['sections'][0]['questions'][0].merge!(change)
      assert_raises(ArgumentError) { parse.call(data) }
    end
    assert_raises(ArgumentError) { parse.call({ 'sections' => base['sections'] * 2 }) }
    blanks = { 'sections' => [{ 'topic' => 'Verbs', 'type' => 'fill_in_the_blanks', 'questions' => [{ 'id' => 'same', 'question' => 'I __.', 'answer' => 'am' }] * 2 }] }
    assert_raises(ArgumentError) { parse.call(blanks) }
  end

  test 'error envelopes cannot masquerade as successful feedback for any managed category' do
    %w[essay speaking_essay speaking_conversation sentence_builder talk_lab_speaking].each do |category|
      %w[grading general_context revised_essay].each do |stage|
        [{ 'error' => 'provider unavailable' }, { 'success' => false, 'message' => 'failed' }].each do |body|
          assert_raises(ArgumentError) { EssayFeedbackValidator.validate!({ 'text' => body.to_json }, stage: stage, category: category) }
        end
      end
    end
    assert EssayFeedbackValidator.validate!({ 'text' => { 'Strengths' => 'Good work.', 'errors' => [] } }, stage: 'general_context', category: 'essay')
  end

  test 'supplement readiness checks the actual scorer for full marks and empty answers' do
    data = { 'sections' => [{ 'topic' => 'Judgement', 'type' => 'true_or_false', 'questions' => [{ 'statement' => 'A valid question.', 'answer' => false }] }] }
    candidate = Struct.new(:grading).new({ 'supplement_practice' => { 'text' => data } })
    assert SupplementPracticeValidator.parse(candidate)
    require 'minitest/mock'
    broken = Object.new
    def broken.calculate = { score: 0, full_score: 0 }
    SupplementPracticeScoringService.stub(:new, broken) do
      assert_raises(ArgumentError) { SupplementPracticeValidator.parse(candidate) }
    end
  end
end
