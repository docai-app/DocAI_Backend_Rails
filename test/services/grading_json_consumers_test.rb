# frozen_string_literal: true

require 'test_helper'

class GradingJsonConsumersTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @grading = EssayGrading.new(id: SecureRandom.uuid, essay_assignment_id: SecureRandom.uuid, grading: {}, meta: {}, general_context: {})
    @controller = Api::V1::EssayGradingsController.new
  end

  %w[essay speaking_conversation speaking_essay].each do |category|
    test "#{category} legacy score zero and full score survive wrappers in lists and reports" do
      data = { 'Overall Score' => 0, 'Full Score' => 20, 'Sentence 1' => { 'sentence' => 'Use `code`.', 'errors' => {} } }
      @grading.grading = { 'data' => { 'text' => "``` json\n#{data.to_json}\n```" } }
      payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: category)
      assert_equal 0, payload[:overall_score]
      assert_equal 20, payload[:the_full_score]
      assert_equal data, @controller.send(:effective_score_sentences, @grading)
    end
  end

  test 'teacher score and deliberately cleared grammar retain priority' do
    @grading.grading = { 'data' => { 'text' => '{broken' } }
    @grading.meta = { 'teacher_review' => { 'score' => { 'data' => { 'Overall Score' => 12, 'Full Score' => 20 } }, 'grammar' => { 'sentences' => [] } } }
    payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'essay')
    assert_equal 12, payload[:overall_score]
    assert_equal 12, @controller.send(:effective_score_sentences, @grading)['Overall Score']
    assert_equal({}, @controller.send(:effective_grammar_sentences, @grading, { 'Sentence 1' => { 'errors' => {} } }))
  end

  test 'sentence builder handles fences without inventing zero for malformed results' do
    @grading.grading = { 'data' => { 'text' => "`#{ { 'results' => [{ 'errors' => [{ 'error1' => 'Correct' }] }, { 'errors' => [{ 'error1' => 'Wrong' }] }] }.to_json}`" } }
    payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'sentence_builder')
    assert_equal 1, payload[:overall_score]
    assert_equal 2, payload[:the_full_score]
    @grading.grading = { 'data' => { 'text' => '`{"results":' } }
    payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'sentence_builder')
    assert_nil payload[:overall_score]
    assert_nil payload[:the_full_score]
  end

  test 'native speaking scores retain priority over old text' do
    @grading.grading = { 'speaking_report' => { 'scores' => { 'overall_band_score' => 7 } }, 'data' => { 'text' => '`{"Overall Score":0}`' } }
    assert_equal 7, EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'speaking_essay')[:overall_score]
  end

  test 'teacher score remains visible when AI text is missing' do
    @grading.meta = { 'teacher_review' => { 'score' => { 'data' => { 'Overall Score' => 0, 'Full Score' => 20 } } } }
    assert_equal 0, EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'essay')[:overall_score]
  end

  test 'invalid numeric summary fields do not coerce to zero' do
    [nil, '', 'null', 'not ready', false, {}, []].each do |value|
      @grading.grading = { 'data' => { 'text' => { 'Overall Score' => value, 'Full Score' => value } } }
      payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'essay')
      assert_nil payload[:score]
      assert_nil payload[:overall_score]
      assert_nil payload[:full_score]
    end
  end

  test 'lowercase numeric score without criteria is preserved' do
    @grading.grading = { 'data' => { 'text' => '`{"overall_score":"6.5","full_score":"9"}`' } }
    payload = EssayGradingSubmissionPayloadBuilder.call(@grading, assignment_category: 'essay')
    assert_equal 6.5, payload[:overall_score]
    assert_equal 9, payload[:full_score]
  end

  test 'structured worksheet uses literal prompts and hides answers for student PDFs' do
    pdf = Object.new
    def pdf.move_down(*); end
    def pdf.height_of(*); 12; end
    def pdf.bounds; Struct.new(:width, :height).new(500, 700); end
    def pdf.cursor; 700; end
    def pdf.text(value, **); (@texts ||= []) << value; end
    def pdf.texts; @texts; end
    questions = { 'quizTitle' => 'Practice', 'sections' => [{ 'topic' => 'Fill in', 'type' => 'fill_in_the_blanks', 'questions' => [{ 'id' => 'blank_1', 'question' => 'Use [[blank_1]] and `code` <tag>.', 'answer' => 'SECRET' }] }] }
    SupplementPracticePdfContent.render(pdf, questions: questions)
    assert_includes pdf.texts, '1. Use ________ and `code` <tag>.'
    assert_no_match(/SECRET|Answer:/, pdf.texts.join)
    SupplementPracticePdfContent.render(pdf, questions: questions, include_answers: true)
    assert_includes pdf.texts, 'Answer: SECRET'
  end

  test 'general context objects fenced content and prose render without exposing damaged data' do
    value = { 'Feedback' => 'Keep `these` words. 中文' }
    [value, value.to_json, "`#{value.to_json}`"].each do |input|
      @grading.general_context = { 'data' => { 'text' => input } }
      assert_equal value, @controller.send(:effective_general_context_data, @grading)
    end
    @grading.general_context = { 'data' => { 'text' => 'Good work, keep practising.' } }
    assert_equal({ 'Feedback' => 'Good work, keep practising.' }, @controller.send(:effective_general_context_data, @grading))
    @grading.general_context = { 'data' => { 'text' => '`{"Feedback":' } }
    assert_nil @controller.send(:effective_general_context_data, @grading)
  end

  test 'Dify scoring parses single fences and object reports' do
    client = SpeakingEssay::DifyScoringClient.allocate
    report = { 'scores' => { 'overall_band_score' => 0 } }
    [report, "`#{report.to_json}`", "```json\n#{report.to_json}\n```"].each do |value|
      assert_equal report, client.send(:parse_report, value)
    end
  end

  test 'unanswered sections count toward total and empty boolean answers are incorrect' do
    questions = { 'sections' => [{ 'topic' => 'True or false', 'type' => 'true_or_false', 'questions' => [{ 'statement' => 'False statement', 'answer' => false }] }] }
    [nil, {}, { 'sections' => [] }, { 'sections' => [{ 'topic' => 'True or false', 'type' => 'true_or_false', 'questions' => [] }] }].each do |answers|
      result = score(questions, answers)
      assert_equal 1, result[:full_score]
      assert_equal 0, result[:score]
      assert_equal 1, result[:incorrect_count]
    end
    [nil, '', 'invalid', false, 'false'].each do |value|
      answers = { 'sections' => [{ 'topic' => 'True or false', 'type' => 'true_or_false', 'questions' => [{ 'statement' => 'False statement', 'user_answer' => value }] }] }
      assert_equal([false, 'false'].include?(value) ? 1 : 0, score(questions, answers)[:score])
    end
  end

  test 'display normalization handles binary UTF8 and invalid bytes without changing source' do
    source = "中文 `word`".b
    assert_equal '中文 `word`', SupplementPracticePdfContent.text(source)
    assert_equal Encoding::ASCII_8BIT, source.encoding
    assert SupplementPracticePdfContent.text("bad\xFF".b).valid_encoding?
  end

  test 'repeated prompts match by stable ID in both scoring and result display' do
    questions = { 'sections' => [{ 'topic' => 'Repeated', 'type' => 'multiple_choice', 'questions' => [
      { 'id' => 'question_0_0', 'question' => 'Pick one', 'answer' => 'A' },
      { 'id' => 'question_0_1', 'question' => 'Pick one', 'answer' => 'B' }
    ] }] }
    answer_section = { 'topic' => 'Repeated', 'type' => 'multiple_choice', 'questions' => [
      { 'id' => 'question_0_1', 'question' => 'Pick one', 'user_answer' => 'B' },
      { 'id' => 'question_0_0', 'question' => 'Pick one', 'user_answer' => 'A' }
    ] }
    assert_equal 2, score(questions, { 'sections' => [answer_section] })[:score]
    controller = Api::V1::SupplementPracticeRecordsController.new
    questions['sections'].first['questions'].each do |question|
      answer = controller.send(:find_user_answer_for_question, answer_section, question, 'multiple_choice')
      assert controller.send(:check_answer_for_question, question, answer, 'multiple_choice')
    end
  end

  private

  def score(questions, answers)
    record = SupplementPracticeRecord.new(questions_data: questions, answers: answers)
    SupplementPracticeScoringService.new(record).calculate
  end
end
