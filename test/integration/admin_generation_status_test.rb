# frozen_string_literal: true
require 'test_helper'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AdminGenerationStatusTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  setup do
    host! 'localhost'
    @previous = ENV['ADMIN_TOKEN']
    ENV['ADMIN_TOKEN'] = 'isolated-admin-status-test-token'
    @headers = { 'Authorization' => "Bearer #{ENV['ADMIN_TOKEN']}" }
    @user = GeneralUser.create!(email: "admin-state-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'State', title: 'State', assignment: 'State', category: 'sentence_builder', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'State', essay: 'Test', status: :draft, grading: {}, meta: {})
    @run = EssayGenerationRun.request!(@grading, kind: 'grading')
    @run.update_columns(state: 'unknown', provider_context: { 'stage' => 'grading', 'key_digest' => 'must-not-leak', 'terminal' => { 'text' => 'private-provider-output' } }, recovery_checked_at: Time.current, attention_required_at: Time.current, recovery_count: 1)
  end
  teardown { ENV['ADMIN_TOKEN'] = @previous }

  test 'monitor and assignment submissions expose safe recovery state without provider output' do
    ["/api/admin/v1/essay_gradings/pending_or_stopped", "/api/admin/v1/essay_assignments/#{@assignment.id}/submissions", "/api/admin/v1/essay_gradings/#{@grading.id}"].each do |url|
      get url, headers: @headers, as: :json
      assert_response :ok, response.body
      body = response.parsed_body
      rows = body['essay_gradings'] || body.dig('data', 'submissions') || [body.dig('data', 'essay_grading')]
      generation = rows.find { |item| item['id'] == @grading.id }['generation']
      assert_equal 'unknown', generation['state']
      assert_equal 'grading', generation['stage']
      assert_equal true, generation['requires_attention']
      assert_equal 1, generation['recovery_count']
      assert generation['recovery_checked_at']
      assert_not_includes response.body, 'must-not-leak'
      assert_not_includes response.body, 'private-provider-output'
    end
  end

  test 'missing generation metadata is null rather than invented queued state' do
    @run.destroy!
    assert_nil Admin::EssayGradings::GenerationStatus.call(@grading.reload)
  end

  test 'legacy malformed error metadata does not break safe diagnostics' do
    @grading.update_columns(meta: { 'last_grading_error' => 'legacy text' })
    result = Admin::EssayGradings::GenerationStatus.call(@grading.reload)
    assert_equal 'unknown', result[:state]
    assert_nil result[:failure_stage]
  end
end
