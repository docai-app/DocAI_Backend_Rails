# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class SupplementPracticeJsonCompatibilityTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @user = GeneralUser.create!(email: "supplement-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', nickname: 'PDF Test', meta: { 'aienglish_role' => 'student' }, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Responsible technology', title: 'Test', assignment: 'Test', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @questions = {
      'quizTitle' => 'Grammar practice 語法練習',
      'sections' => [
        { 'topic' => 'Word choice', 'type' => 'multiple_choice', 'questions' => [{ 'question' => 'Choose `break` (3.14).', 'options' => ['A. break', 'B. brake'], 'answer' => 'A. break' }] },
        { 'topic' => 'Judgement', 'type' => 'true_or_false', 'questions' => [{ 'statement' => 'This sentence is correct.', 'answer' => false }] },
        { 'topic' => 'Fill in', 'type' => 'fill_in_the_blanks', 'questions' => [{ 'id' => 'saved-blank-id', 'question' => 'I ___ happy.', 'answer' => 'am' }] }
      ]
    }
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: @assignment.topic, essay: 'A response', status: :draft, grading: { 'supplement_practice' => { 'text' => @questions.to_json } }, general_context: {}, revised_essay: {}, meta: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @base = "/api/v1/essay_gradings/#{@grading.id}/supplement_practice"
  end

  ['plain', 'single', 'fenced', 'object', 'double_encoded'].each do |format|
    test "#{format} questions read save reload submit and reject duplicate" do
      value = case format
              when 'single' then "`#{@questions.to_json}`"
              when 'fenced' then "```json\n#{@questions.to_json}\n```"
              when 'object' then @questions
              when 'double_encoded' then @questions.to_json.to_json
              else @questions.to_json
              end
      update_text(value)
      get @base, headers: @headers, as: :json
      assert_response :ok, response.body
      sections = response.parsed_body.fetch('data').fetch('sections')
      assert_equal ['question_0_0', 'question_1_0', 'saved-blank-id'], sections.map { |section| section['questions'].first['id'] }
      answers = { sections: sections.map { |section| section.merge('questions' => section['questions'].map { |q| q.merge('user_answer' => q['answer']) }) } }
      post "#{@base}/draft", params: { answers: answers, using_time: 17 }, headers: @headers, as: :json
      assert_response :ok, response.body
      record_id = response.parsed_body.dig('data', 'id')
      get @base, headers: @headers, as: :json
      assert_equal record_id, response.parsed_body.dig('data', 'existing_record', 'id')
      assert_equal false, response.parsed_body.dig('data', 'existing_record', 'answers', 'sections', 1, 'questions', 0, 'user_answer')
      post "#{@base}/submit", params: { answers: answers, using_time: 23 }, headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal 3, response.parsed_body.dig('data', 'score').to_f
      assert_equal 3, response.parsed_body.dig('data', 'full_score').to_f
      assert_equal record_id, response.parsed_body.dig('data', 'id')
      assert_equal 23, SupplementPracticeRecord.find(record_id).using_time
      get "/api/v1/supplement_practice_records/#{record_id}", headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal true, response.parsed_body.dig('data', 'sections', 1, 'questions', 0, 'is_correct')
      get "/api/v1/supplement_practice_records/#{record_id}/download_report"
      assert_pdf
      post "#{@base}/submit", params: { answers: answers }, headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal 1, SupplementPracticeRecord.where(essay_grading: @grading).count
    end
  end

  test 'damaged structured exercises fail read save and submit without persisting records' do
    ['`{"sections":', '{"sections":[]}', 'null', 'false', '0', { 'sections' => [{ 'type' => 'wrong' }] }].each do |value|
      update_text(value)
      get @base, headers: @headers, as: :json
      assert_friendly_invalid
      %w[draft submit].each do |action|
        post "#{@base}/#{action}", params: { answers: { sections: [] } }, headers: @headers, as: :json
        assert_friendly_invalid
      end
      assert_empty SupplementPracticeRecord.where(essay_grading: @grading)
    end
  end

  test 'genuine legacy prose retains document compatibility' do
    update_text("# Practice\n\n1. Write a sentence containing 3.14 and `code`.\n")
    get @base, headers: @headers, as: :json
    assert_response :ok
    assert_equal 'old_data', response.parsed_body['code']
    get_pdf
    assert_pdf
  end

  test 'fenced structured PDF uses question renderer and works with broken unrelated grading data' do
    update_text("```json\n#{@questions.to_json}\n```")
    @grading.update_columns(grading: @grading.grading.merge('data' => { 'text' => 'broken unrelated score' }))
    get_pdf
    assert_pdf
    if ENV['SAVE_GRADING_PDF_FIXTURES'] == '1'
      FileUtils.mkdir_p(Rails.root.join('tmp/pdfs'))
      File.binwrite(Rails.root.join('tmp/pdfs/supplement-json-compatibility.pdf'), response.body)
    end
  end

  test 'broken and missing exercises never download a success-shaped report' do
    update_text('`{"sections":')
    get_pdf
    assert_friendly_invalid
    update_text(nil)
    get_pdf
    assert_response :not_found
    assert_equal 'application/json', response.media_type
  end

  test 'PDF renderer exceptions return a friendly real 500 rather than a 200 error document' do
    Prawn::Document.stub(:new, ->(*) { raise StandardError, 'invalid byte sequence in UTF-8' }) do
      get_pdf
      assert_response :internal_server_error
      assert_equal false, response.parsed_body['success']
      assert_no_match(/UTF-8|JSON|byte|sequence/, response.parsed_body['error'])
      assert_equal 'application/json', response.media_type
    end
  end

  test 'exercise actions still require authentication' do
    get @base, as: :json
    assert_response :unauthorized
    %w[draft submit].each do |action|
      post "#{@base}/#{action}", params: { answers: { sections: [] } }, as: :json
      assert_response :unauthorized
    end
  end

  test 'long worksheet remains a valid multi-page student PDF' do
    @questions['sections'].first['questions'] = 25.times.map do |index|
      { 'question' => "Long question #{index + 1}: #{'Write a careful response using the words given. ' * 3}", 'options' => ['A. One', 'B. Two'], 'answer' => 'A. One' }
    end
    update_text("```json\n#{@questions.to_json}\n```")
    get "/api/v1/essay_gradings/#{@grading.id}/download_supplement_practice", params: { role: 'student' }
    assert_pdf
    if ENV['SAVE_GRADING_PDF_FIXTURES'] == '1'
      FileUtils.mkdir_p(Rails.root.join('tmp/pdfs'))
      File.binwrite(Rails.root.join('tmp/pdfs/supplement-multipage-student.pdf'), response.body)
    end
  end

  test 'incomplete submission still has full denominator and readable results' do
    post "#{@base}/submit", params: { answers: { sections: [] } }, headers: @headers, as: :json
    assert_response :ok, response.body
    assert_equal 0, response.parsed_body.dig('data', 'score').to_f
    assert_equal 3, response.parsed_body.dig('data', 'full_score').to_f
    record_id = response.parsed_body.dig('data', 'id')
    get "/api/v1/supplement_practice_records/#{record_id}", headers: @headers, as: :json
    assert_response :ok, response.body
    assert_equal false, response.parsed_body.dig('data', 'sections', 1, 'questions', 0, 'is_correct')
    get "/api/v1/supplement_practice_records/#{record_id}/download_report"
    assert_pdf
  end

  test 'missing grading and assignment downloads return real 404 statuses' do
    missing_id = SecureRandom.uuid
    %w[download_supplement_practice download_report].each do |action|
      get "/api/v1/essay_gradings/#{missing_id}/#{action}"
      assert_response :not_found, response.body
      assert_equal false, response.parsed_body['success']
    end
    get "/api/v1/essay_assignments/#{missing_id}/download_reports"
    assert_response :not_found, response.body
    assert_equal false, response.parsed_body['success']
  end

  %w[essay speaking_essay speaking_conversation sentence_builder].each do |category|
    test "#{category} normal report downloads with wrapped feedback" do
      @assignment.update_columns(category: category, meta: { 'vocabs' => [{ 'word' => 'happy', 'pos' => 'adjective' }] })
      content = if category == 'sentence_builder'
                  { 'results' => [{ 'original_sentence' => 'I am happy.', 'errors' => [{ 'error1' => 'Correct' }] }] }
                else
                  { 'Overall Score' => 7, 'Full Score' => 9, 'Sentence 1' => { 'sentence' => 'I am happy.', 'errors' => {} } }
                end
      @grading.update_columns(
        grading: { 'data' => { 'text' => "```json\n#{content.to_json}\n```" } },
        general_context: { 'data' => { 'text' => '`{"Feedback":"Good work. 保留中文。"}`' } },
        revised_essay: { 'data' => { 'text' => 'I am happy.' } }
      )
      get "/api/v1/essay_gradings/#{@grading.id}/download_report", params: { role: 'teacher' }
      assert_pdf
    end
  end

  private

  def update_text(text)
    @grading.update_columns(grading: { 'supplement_practice' => { 'text' => text } })
  end

  def get_pdf
    get "/api/v1/essay_gradings/#{@grading.id}/download_supplement_practice", params: { role: 'teacher' }
  end

  def assert_pdf
    assert_response :ok, response.body[0, 200]
    assert_equal 'application/pdf', response.media_type
    assert response.body.b.start_with?('%PDF-'.b)
  end

  def assert_friendly_invalid
    assert_response :unprocessable_entity, response.body
    assert_equal false, response.parsed_body['success']
    assert_no_match(/JSON|parser|UTF-8|undefined|sections|ArgumentError/i, response.parsed_body['error'])
  end
end
