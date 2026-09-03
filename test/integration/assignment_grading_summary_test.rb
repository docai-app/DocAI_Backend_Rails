# frozen_string_literal: true

require 'test_helper'

class AssignmentGradingSummaryTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @teacher = GeneralUser.create!(
      email: "summary-#{SecureRandom.hex(6)}@example.test", password: 'Password123!',
      nickname: 'Summary test', meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => ['essay'] },
      konnecai_tokens: {}
    )
    @assignment = EssayAssignment.create!(
      general_user: @teacher, topic: 'Summary test', title: 'Summary test',
      assignment: 'Summary test', category: 'essay', rubric: { 'name' => 'Test' }, meta: {}
    )
    @grading = EssayGrading.create!(
      general_user: @teacher, essay_assignment: @assignment, topic: 'Summary test',
      essay: 'A sample response.', status: :draft, grading: {}, meta: {},
      general_context: {}, revised_essay: {}
    )
    token, = Warden::JWTAuth::UserEncoder.new.call(@teacher, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @feedback = {
      'Overall Score' => 51, 'Full Score' => 100,
      'Sentence 1' => {
        'sentence' => 'She go.',
        'errors' => { 'error1' => { 'word' => 'go', 'category' => 'A', 'error_id' => 'A1', 'explanation' => 'Use goes.' } }
      }
    }
  end

  %w[plain single fenced object double_encoded].each do |format|
    test "#{format} assignment summary matches detail and repairs stale counters without rewriting" do
      text = case format
             when 'single' then "`#{@feedback.to_json}`"
             when 'fenced' then "```json\n#{@feedback.to_json}\n```"
             when 'object' then @feedback
             when 'double_encoded' then @feedback.to_json.to_json
             else @feedback.to_json
             end
      store_feedback(text)
      original = @grading.reload.attributes
      summary = get_summary
      assert_equal 51, summary['score']
      assert_equal 51, summary['overall_score']
      assert_equal 100, summary['full_score']
      assert_equal 1, summary['number_of_suggestion']
      assert_not summary.key?('grading'), 'List must remain a compact response, not fetch all grading detail.'
      get "/api/v1/essay_gradings/#{@grading.id}", headers: @headers, as: :json
      assert_response :ok, response.body
      detail = response.parsed_body.fetch('essay_grading')
      assert_equal summary['overall_score'], detail['overall_score']
      assert_equal summary['full_score'], detail['full_score']
      assert_equal original, @grading.reload.attributes
    end
  end

  test 'genuine zero and teacher overrides remain authoritative in summary and detail' do
    store_feedback("`#{@feedback.to_json}`")
    @grading.update_columns(meta: { 'teacher_review' => {
      'score' => { 'data' => { 'Overall Score' => 0, 'Full Score' => 100 } },
      'grammar' => { 'sentences' => [] }
    } })
    summary = get_summary
    assert_equal 0, summary['overall_score']
    assert_equal 0, summary['score']
    assert_equal 100, summary['full_score']
    assert_equal 0, summary['number_of_suggestion']
    get "/api/v1/essay_gradings/#{@grading.id}", headers: @headers, as: :json
    assert_response :ok
    assert_equal 0, response.parsed_body.dig('essay_grading', 'overall_score')
  end

  test 'damaged grading summary stays unknown instead of returning fabricated zero' do
    store_feedback('`{"Overall Score":')
    summary = get_summary
    %w[score overall_score full_score number_of_suggestion].each { |key| assert_nil summary[key], key }
  end


  CASES = [
    ['speaking_conversation', 'wrapped suggestions', { 'data' => { 'text' => '`{"Sentence1":{"errors":{"A1":{"word":"go"}}}}`' }, 'number_of_suggestion' => 0 }, {}, nil, {}, [nil, nil, 1]],
    ['sentence_builder', 'raw results', { 'data' => { 'text' => '`{"results":[{"errors":[{"error1":"Correct"}]},{"errors":[{"error1":"Wrong"}]}]}`' } }, {}, nil, {}, [1, 2, 1]],
    ['sentence_builder', 'teacher overrides native score', { 'sentence_builder' => { 'score' => 1, 'full_score' => 2 } }, { 'teacher_review' => { 'grammar' => { 'sentences' => [{ 'isCorrect' => true, 'errors' => [] }, { 'isCorrect' => true, 'errors' => [] }] } } }, nil, {}, [2, 2, 0]],
    ['sentence_builder', 'empty teacher review is not raw fallback', { 'sentence_builder' => { 'score' => 2, 'full_score' => 2 } }, { 'teacher_review' => { 'grammar' => { 'sentences' => [] } } }, nil, {}, [nil, 2, 0]],
    ['sentence_builder', 'partial result not a smaller full score', { 'data' => { 'text' => '{"results":[{"errors":[]}]}' } }, {}, nil, { 'vocabs' => [{}, {}, {}] }, [nil, 3, 0]],
    ['sentence_builder', 'empty errors counts as correct sentence', { 'data' => { 'text' => '{"results":[{"errors":[]},{"errors":[]}]}' } }, {}, nil, {}, [2, 2, 0]],
    ['sentence_builder', 'malformed sentence not zero', { 'data' => { 'text' => '{"results":[{}]}' } }, {}, nil, {}, [nil, 1, nil]],
    ['speaking_essay', 'native score', { 'speaking_report' => { 'scores' => { 'overall_band_score' => 7 } } }, {}, nil, {}, [7, 9, nil]],
    ['speaking_essay', 'wrapped scores', { 'data' => { 'text' => '`{"scores":{"overall_band_score":7}}`' } }, {}, nil, {}, [7, 9, nil]],
    ['speaking_essay', 'wrapped legacy full score', { 'data' => { 'text' => '`{"Overall Score":16,"Full Score":20}`' } }, {}, nil, {}, [16, 20, nil]],
    ['speaking_essay', 'teacher overrides native band', { 'speaking_report' => { 'scores' => { 'overall_band_score' => 7 } } }, { 'teacher_review' => { 'score' => { 'data' => { 'Overall Score' => 18, 'Full Score' => 20 } } } }, nil, {}, [18, 20, nil]],
    ['comprehension', 'full score without questions count', { 'comprehension' => { 'score' => 3, 'full_score' => 5 } }, {}, nil, {}, [3, 5, nil]],
    ['comprehension', 'questions count fallback', { 'comprehension' => { 'score' => 3, 'questions_count' => 5 } }, {}, nil, {}, [3, 5, nil]],
    ['listening', 'normal score', { 'listening' => { 'score' => 3, 'full_score' => 5 } }, {}, nil, {}, [3, 5, nil]],
    ['speaking_pronunciation', 'decimal preserved', {}, {}, 87.5, {}, [87.5, 100, nil]],
    ['sentence_puzzle', 'native attempt', {}, { 'sentence_puzzle_attempt' => { 'score' => 2, 'total' => 3 } }, nil, {}, [2, 3, nil]],
    ['sentence_puzzle', 'grading attempt', { 'sentence_puzzle_attempt' => { 'score' => 2, 'total' => 3 } }, {}, nil, {}, [2, 3, nil]],
    ['sentence_puzzle', 'nested attempt', { 'meta' => { 'sentence_puzzle_attempt' => { 'score' => 2, 'total' => 3 } } }, {}, nil, {}, [2, 3, nil]],
    ['sentence_puzzle', 'wrapped legacy attempt', { 'data' => { 'text' => '`{"sentence_puzzle_attempt":{"score":2,"total":3}}`' } }, {}, nil, {}, [2, 3, nil]]
  ].freeze

  CASES.each do |category, scenario, data, meta, raw_score, assignment_meta, expected|
    test "#{category} #{scenario} has consistent read-only list and detail metrics" do
      @assignment.update_columns(category: category, meta: assignment_meta)
      @grading.update_columns(status: EssayGrading.statuses[:graded], grading: data, meta: meta, score: raw_score)
      assert_metrics_consistent(expected)
    end
  end

  ZERO_CASES = {
    'essay' => [{ 'data' => { 'text' => '`{"Overall Score":0,"Full Score":100}`' } }, {}, nil, 100],
    'speaking_conversation' => [{ 'data' => { 'text' => '`{"Overall Score":0,"Full Score":100}`' } }, {}, nil, 100],
    'sentence_builder' => [{ 'data' => { 'text' => '{"results":[{"errors":[{"error1":"Wrong"}]}]}' } }, {}, nil, 1],
    'speaking_essay' => [{ 'speaking_report' => { 'scores' => { 'overall_band_score' => 0 } } }, {}, nil, 9],
    'comprehension' => [{ 'comprehension' => { 'score' => 0, 'questions_count' => 5 } }, {}, nil, 5],
    'listening' => [{ 'listening' => { 'score' => 0, 'full_score' => 5 } }, {}, nil, 5],
    'speaking_pronunciation' => [{}, {}, 0, 100],
    'sentence_puzzle' => [{}, { 'sentence_puzzle_attempt' => { 'score' => 0, 'total' => 3 } }, nil, 3]
  }.freeze

  ZERO_CASES.each do |category, (data, meta, raw_score, full_score)|
    test "#{category} genuine zero is preserved in list and detail" do
      @assignment.update_columns(category: category, meta: {})
      @grading.update_columns(status: EssayGrading.statuses[:graded], grading: data, meta: meta, score: raw_score)
      assert_metrics_consistent([0, full_score, category == 'sentence_builder' ? 1 : nil])
    end

    test "#{category} missing result is not a zero score" do
      @assignment.update_columns(category: category, meta: {})
      @grading.update_columns(status: EssayGrading.statuses[:graded], grading: {}, meta: {}, score: nil)
      assert_metrics_consistent([nil, category == 'speaking_pronunciation' ? 100 : nil, nil])
    end
  end

  private

  def assert_metrics_consistent(expected)
    before = @grading.reload.attributes
    summary = get_summary
    get "/api/v1/essay_gradings/#{@grading.id}", headers: @headers, as: :json
    assert_response :ok, response.body
    detail = response.parsed_body.fetch('essay_grading')
    assert_equal expected, summary.values_at('score', 'full_score', 'number_of_suggestion')
    assert_equal expected, detail.values_at('score', 'full_score', 'number_of_suggestion')
    assert_equal summary.slice('overall_score', 'scores', 'metrics_version'), detail.slice('overall_score', 'scores', 'metrics_version')
    assert_equal 1, summary['metrics_version']
    assert_equal before, @grading.reload.attributes
    assert_not summary.key?('grading'), 'List must not return full AI feedback per submission.'
  end

  def store_feedback(text)
    # No real AI workflow; reproduce old records with a cached zero counter.
    @grading.update_columns(status: EssayGrading.statuses[:graded], grading: {
      'data' => { 'text' => text }, 'number_of_suggestion' => 0
    })
  end

  def get_summary
    get "/api/v1/essay_assignments/#{@assignment.id}", headers: @headers, as: :json
    assert_response :ok, response.body
    response.parsed_body.fetch('essay_gradings').find { |item| item['id'] == @grading.id }
  end
end
