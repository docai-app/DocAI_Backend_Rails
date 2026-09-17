# frozen_string_literal: true
require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class SubmissionTransitionGuardTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'localhost'
    @user = GeneralUser.create!(email: "transition-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Test', title: 'Test', assignment: 'Test', category: 'sentence_builder', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Test', essay: 'I am happy.', status: :draft, grading: { 'sentence_builder' => [{ 'sentence' => 'I am happy.' }] }, meta: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @url = "/api/v1/essay_gradings/#{@grading.id}.json"
    EssayGenerationJob.clear
  end

  %w[essay sentence_builder speaking_essay speaking_conversation speaking_pronunciation sentence_puzzle].each do |category|
    %w[pending graded stopped].each do |state|
      test "#{category} #{state} cannot become pending or draft through ordinary update" do
        @assignment.update_columns(category: category)
        @grading.update_columns(status: EssayGrading.statuses.fetch(state))
        original = @grading.reload.attributes
        ['pending', 'draft', EssayGrading.statuses.fetch('pending'), EssayGrading.statuses.fetch('draft')].each do |target|
          put @url, params: { essay_grading: { status: target, sentence_builder: [{ sentence: 'Stale answer' }] } }, headers: @headers, as: :json
          assert_response :conflict, response.body
          assert_equal original, @grading.reload.attributes
          assert_empty EssayGenerationJob.jobs
        end
      end
    end
  end

  test 'first draft submission works and repeated submit or late draft cannot overwrite it' do
    put @url, params: { essay_grading: { status: 'draft', sentence_builder: [{ sentence: 'Saved answer' }] } }, headers: @headers, as: :json
    assert_response :ok, response.body
    put @url, params: { essay_grading: { status: 'pending', sentence_builder: [{ sentence: 'Final answer' }] } }, headers: @headers, as: :json
    assert_response :ok, response.body
    assert_equal 'pending', @grading.reload.status
    assert_equal 1, EssayGenerationJob.jobs.size
    %w[pending draft].each do |status|
      put @url, params: { essay_grading: { status: status, sentence_builder: [{ sentence: 'Old answer' }] } }, headers: @headers, as: :json
      assert_response :conflict
      assert_equal 'Final answer', @grading.reload.grading.dig('sentence_builder', 0, 'sentence')
    end
    assert_equal 1, EssayGenerationJob.jobs.size
  end

  test 'ordinary metadata edit does not force a completed record back into processing' do
    @grading.update_columns(status: EssayGrading.statuses[:graded])
    put @url, params: { essay_grading: { using_time: 12 } }, headers: @headers, as: :json
    assert_response :ok, response.body
    assert_equal 'graded', @grading.reload.status
    assert_empty EssayGenerationJob.jobs
  end
end
