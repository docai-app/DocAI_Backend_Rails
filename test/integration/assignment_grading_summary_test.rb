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

  private

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
