# frozen_string_literal: true

require 'test_helper'
require 'pdf/reader'
require 'stringio'
require 'zip'

class SentencePuzzleDraftAndReportTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai-dev.m2mda.com'
    @teacher = create_user!('teacher')
    @student = create_user!('student')
    @assignment = EssayAssignment.create!(
      general_user: @teacher,
      topic: 'Build the sentence',
      assignment: 'Sentence Puzzle Draft Test',
      title: 'Sentence Puzzle Draft Test',
      category: 'sentence_puzzle',
      meta: {
        'sentence_puzzle' => {
          'max_attempts_per_question' => 3,
          'show_answer_after_max_attempts' => true,
          'questions' => [
            {
              'id' => 'question_1',
              'order' => 1,
              'correct_sentence' => 'I like apples & pears <today>.',
              'blocks' => [
                { 'id' => 'block_1', 'text' => 'I', 'order' => 1 },
                { 'id' => 'block_2', 'text' => 'like', 'order' => 2 },
                { 'id' => 'block_3', 'text' => 'apples', 'order' => 3 },
                { 'id' => 'block_4', 'text' => '&', 'order' => 4 },
                { 'id' => 'block_5', 'text' => 'pears', 'order' => 5 },
                { 'id' => 'block_6', 'text' => '<today>', 'order' => 6 },
                { 'id' => 'block_7', 'text' => '.', 'order' => 7 }
              ]
            }
          ]
        }
      }
    )
    @token = sign_in_token(@student)
  end

  test 'draft is recovered, reused, submitted in place, and downloadable as PDF' do
    post grading_collection_path,
         params: { essay_grading: draft_payload(selected_blocks: %w[block_1 block_2]) },
         headers: auth_headers,
         as: :json

    assert_response :created
    first_body = JSON.parse(response.body)
    draft_id = first_body.dig('essay_grading', 'id')
    assert_equal 'draft', first_body.dig('essay_grading', 'status')
    assert_equal 1, @assignment.essay_gradings.where(general_user: @student, status: :draft).count
    assert_equal 0, @assignment.reload.number_of_submission

    post grading_collection_path,
         params: { essay_grading: draft_payload(selected_blocks: %w[block_1 block_2 block_3]) },
         headers: auth_headers,
         as: :json

    assert_response :success
    second_body = JSON.parse(response.body)
    assert_equal draft_id, second_body.dig('essay_grading', 'id')
    assert_equal 1, @assignment.essay_gradings.where(general_user: @student, status: :draft).count

    get current_draft_path, headers: auth_headers, as: :json

    assert_response :success
    recovered = JSON.parse(response.body).fetch('essay_grading')
    assert_equal draft_id, recovered['id']
    assert_equal %w[block_1 block_2 block_3],
                 recovered.dig('meta', 'sentence_puzzle_attempt', 'progress', 'selected_block_order')

    put "/api/v1/essay_gradings/#{draft_id}.json",
        params: { essay_grading: submitted_payload },
        headers: auth_headers,
        as: :json

    assert_response :success
    submitted = EssayGrading.find(draft_id)
    assert_equal 'graded', submitted.status
    assert_equal 1, submitted.score.to_i
    assert_equal 'submitted', submitted.meta.dig('sentence_puzzle_attempt', 'status')
    assert_equal 1, submitted.meta.dig('sentence_puzzle_attempt', 'total')
    assert_equal true, submitted.meta.dig('sentence_puzzle_attempt', 'answers', 0, 'is_correct')
    assert_equal 3, submitted.meta.dig('sentence_puzzle_attempt', 'answers', 0, 'attempts_used')
    assert_equal 'I like apples & pears <today>.',
                 submitted.meta.dig('sentence_puzzle_attempt', 'answers', 0, 'correct_sentence')
    assert_equal 'I like apples & pears <today>.',
                 submitted.meta.dig('sentence_puzzle_attempt', 'answers', 0, 'student_sentence')
    assert_equal 1, @assignment.essay_gradings.where(general_user: @student).count
    assert_equal 1, @assignment.reload.number_of_submission

    get current_draft_path, headers: auth_headers, as: :json
    assert_response :success
    assert_nil JSON.parse(response.body)['essay_grading']

    get "/api/v1/essay_gradings/#{draft_id}/download_report"
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert response.body.start_with?('%PDF')
    assert_sentence_puzzle_report_content(response.body)

    get "/api/v1/essay_assignments/#{@assignment.id}/download_reports"
    assert_response :success
    assert_equal 'application/zip', response.media_type
    Zip::File.open_buffer(response.body) do |zip|
      assert_equal 1, zip.entries.length
      report_body = zip.entries.first.get_input_stream.read
      assert report_body.start_with?('%PDF')
      assert_sentence_puzzle_report_content(report_body)
    end
  end

  test 'submitted score is recalculated and invalid block selections are rejected' do
    payload = submitted_payload
    answer = payload.dig(:meta, :sentence_puzzle_attempt, :answers, 0)
    answer[:student_block_order] = Array.new(7, 'block_1')

    post grading_collection_path,
         params: { essay_grading: payload },
         headers: auth_headers,
         as: :json

    assert_response :created
    grading = EssayGrading.find(JSON.parse(response.body).dig('essay_grading', 'id'))
    verified_answer = grading.meta.dig('sentence_puzzle_attempt', 'answers', 0)

    assert_equal 0, grading.score.to_i
    assert_equal 1, grading.meta.dig('sentence_puzzle_attempt', 'total')
    assert_equal false, verified_answer['is_correct']
    assert_equal [], verified_answer['student_block_order']
    assert_equal '', verified_answer['student_sentence']
  end

  private

  def grading_collection_path
    "/api/v1/essay_assignments/#{@assignment.code}/essay_gradings.json"
  end

  def current_draft_path
    "/api/v1/essay_assignments/#{@assignment.code}/essay_gradings/current_draft"
  end

  def draft_payload(selected_blocks:)
    {
      essay: 'Sentence Puzzle draft',
      status: 'draft',
      meta: {
        sentence_puzzle_attempt: {
          status: 'draft',
          score: 0,
          total: 1,
          answers: [],
          progress: {
            current_question_id: 'question_1',
            current_question_order: 1,
            selected_block_order: selected_blocks,
            attempts_by_question: { question_1: 1 },
            saved_at: Time.current.iso8601
          }
        }
      }
    }
  end

  def submitted_payload
    {
      essay: 'Sentence Puzzle Score: 1/1',
      status: 'graded',
      meta: {
        sentence_puzzle_attempt: {
          status: 'submitted',
          score: 999,
          total: 999,
          answers: [
            {
              question_id: 'question_1',
              question_order: 1,
              correct_sentence: 'Tampered correct sentence',
              attempts_used: 99,
              is_correct: false,
              student_block_order: %w[block_1 block_2 block_3 block_4 block_5 block_6 block_7],
              student_sentence: 'Tampered student sentence',
              revealed_answer: false,
              answered_at: Time.current.iso8601
            }
          ]
        }
      }
    }
  end

  def create_user!(role)
    user = GeneralUser.create!(
      email: "sentence-puzzle-#{role}-#{SecureRandom.hex(4)}@example.test",
      password: 'Password123!',
      nickname: role.titleize,
      meta: {
        'aienglish_role' => role,
        'aienglish_features_list' => ['sentence_puzzle']
      },
      konnecai_tokens: {}
    )
    user.create_energy(value: 100) unless user.energy
    user
  end

  def sign_in_token(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    "Bearer #{token}"
  end

  def auth_headers
    { 'Authorization' => @token }
  end

  def assert_sentence_puzzle_report_content(pdf_body)
    report_text = PDF::Reader.new(StringIO.new(pdf_body)).pages.map(&:text).join("\n")

    assert_includes report_text, 'Sentence Puzzle Results'
    assert_includes report_text, 'Your sentence'
    assert_includes report_text, 'Correct sentence'
    assert_includes report_text, 'I like apples & pears <today>.'
    refute_includes report_text, 'Answer revealed'
    refute_includes report_text, 'Report Type'
    refute_includes report_text, '(continued)'
  end
end
