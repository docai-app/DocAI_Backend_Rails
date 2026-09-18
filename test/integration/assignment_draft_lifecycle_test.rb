# frozen_string_literal: true
raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'sidekiq/testing'
require 'minitest/mock'
Sidekiq::Testing.fake!

class AssignmentDraftLifecycleTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)
  CATEGORIES = %w[essay sentence_builder comprehension sentence_puzzle speaking_essay speaking_conversation speaking_pronunciation listening talk_lab_speaking].freeze

  setup do
    host! 'localhost'
    @user = GeneralUser.create!(email: "draft-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    EssayGenerationJob.clear
    ActiveStorage::Current.url_options = { host: 'http://localhost' }
    # EssayGrading explicitly selects Azure; override only this isolated test's
    # attachment reflection so multipart requests cannot reach cloud storage.
    @file_service = EssayGrading.attachment_reflections['file'].options[:service_name]
    EssayGrading.attachment_reflections['file'].options[:service_name] = :test
  end

  teardown do
    EssayGrading.attachment_reflections['file'].options[:service_name] = @file_service
  end

  CATEGORIES.each do |category|
    test "#{category} restores one draft, versions writes, replays submission and rejects stale tabs" do
      assignment = make_assignment(category)
      open_key = SecureRandom.uuid
      post draft_url(assignment), params: { request_id: open_key }, headers: @headers, as: :json
      assert_response :ok, response.body
      id = response.parsed_body.dig('essay_grading', 'id')
      assert_equal 0, assignment.reload.number_of_submission
      post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal id, response.parsed_body.dig('essay_grading', 'id')
      row = EssayGrading.find(id)
      if category == 'speaking_essay'
        # Local ActiveStorage test disk; no Azure requests.
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('fixture audio'), filename: 'fixture.mp3', content_type: 'audio/mpeg', service_name: :test)
        row.file.attach(blob)
      end
      saved = { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload(category, 'draft') }
      put grading_url(id), params: saved, headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal 1, response.parsed_body.dig('essay_grading', 'meta', 'assignment_draft_session', 'revision')
      final = { request_id: SecureRandom.uuid, draft_revision: 1, essay_grading: payload(category, 'pending') }
      put grading_url(id), params: final, headers: @headers, as: :json
      assert_response :ok, response.body
      refute_equal 'draft', row.reload.status
      expected = row.attributes
      jobs = EssayGenerationJob.jobs.size
      put grading_url(id), params: final, headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal id, response.parsed_body.dig('essay_grading', 'id')
      assert_equal expected, row.reload.attributes
      assert_equal jobs, EssayGenerationJob.jobs.size
      put grading_url(id), params: saved, headers: @headers, as: :json
      assert_response :conflict
      assert_equal expected, row.reload.attributes
      assert_equal 1, assignment.essay_gradings.count
      assert_equal 0, assignment.essay_gradings.where(status: :draft).count
      assert_equal 1, assignment.reload.number_of_submission
      post draft_url(assignment), params: { request_id: open_key }, headers: @headers, as: :json
      assert_response :ok
      assert_equal id, response.parsed_body.dig('essay_grading', 'id')
      post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
      assert_response :ok
      refute_equal id, response.parsed_body.dig('essay_grading', 'id'), 'explicit new opening may start another attempt'
    end

    test "#{category} rejects duplicate model drafts and older versions without destroying work" do
      assignment = make_assignment(category)
      session = AssignmentDraftSession.new(assignment: assignment, user: @user)
      row = session.prepare(SecureRandom.uuid)
      assert_raises(ActiveRecord::RecordInvalid) do
        EssayGrading.create!(essay_assignment: assignment, general_user: @user, status: :draft)
      end
      first = { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload(category, 'draft') }
      put grading_url(row.id), params: first, headers: @headers, as: :json
      assert_response :ok, response.body
      put grading_url(row.id), params: first.merge(request_id: SecureRandom.uuid), headers: @headers, as: :json
      assert_response :conflict
      post "/api/v1/essay_assignments/#{assignment.code}/essay_gradings.json", params: { essay_grading: payload(category, 'pending') }, headers: @headers, as: :json
      assert_response :conflict
      assert_equal 1, assignment.essay_gradings.count
      assert row.reload.draft?
    end
  end

  test 'preset answers share the version lock and stale saves cannot overwrite submitted answers' do
    assignment = make_assignment('speaking_conversation')
    assignment.update!(meta: { 'speaking_conversation' => { 'mode' => 'preset_questions', 'questions' => [{ 'id' => 'q1', 'text' => 'Introduce yourself.', 'order' => 1 }] } })
    post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
    assert_response :ok
    id = response.parsed_body.dig('essay_grading', 'id')
    answer = { request_id: SecureRandom.uuid, draft_revision: 0, answer: { answer_text: 'My name is Alex.', question_order: 1 } }
    patch "/api/v1/essay_gradings/#{id}/speaking_conversation/answers/q1", params: answer, headers: @headers, as: :json
    assert_response :ok, response.body
    final = { request_id: SecureRandom.uuid, draft_revision: 1 }
    2.times do
      post "/api/v1/essay_gradings/#{id}/speaking_conversation/submit", params: final, headers: @headers, as: :json
      assert_response :ok, response.body
    end
    assert_equal 1, EssayGenerationJob.jobs.size
    patch "/api/v1/essay_gradings/#{id}/speaking_conversation/answers/q1", params: answer.merge(request_id: SecureRandom.uuid), headers: @headers, as: :json
    assert_response :conflict
    assert_equal 'My name is Alex.', EssayGrading.find(id).grading.dig('speaking_conversation', 'answers', 0, 'answer_text')
  end

  test 'historical duplicate drafts are preserved and reported as a conflict' do
    assignment = make_assignment('essay')
    first = EssayGrading.create!(essay_assignment: assignment, general_user: @user, status: :draft)
    data = first.attributes.except('id').merge('id' => SecureRandom.uuid)
    EssayGrading.insert_all!([data]) # Simulate pre-release historical data only.
    post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
    assert_response :conflict
    assert_equal 2, assignment.essay_gradings.count
  end

  test 'another student cannot update a draft and receives their own draft on opening' do
    assignment = make_assignment('essay')
    owner_draft = AssignmentDraftSession.new(assignment: assignment, user: @user).prepare(SecureRandom.uuid)
    other = GeneralUser.create!(email: "draft-other-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    token, = Warden::JWTAuth::UserEncoder.new.call(other, :general_user, nil)
    headers = { 'Authorization' => "Bearer #{token}" }
    put grading_url(owner_draft.id), params: { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload('essay', 'pending') }, headers: headers, as: :json
    assert_response :forbidden
    assert owner_draft.reload.draft?
    post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: headers, as: :json
    assert_response :ok
    refute_equal owner_draft.id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal other.id, EssayGrading.find(response.parsed_body.dig('essay_grading', 'id')).general_user_id
  end

  test 'key reuse with changed answers conflicts; deletion of an excluded draft keeps the counter' do
    assignment = make_assignment('essay')
    row = AssignmentDraftSession.new(assignment: assignment, user: @user).prepare(SecureRandom.uuid)
    body = { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload('essay', 'draft') }
    put grading_url(row.id), params: body, headers: @headers, as: :json
    assert_response :ok
    changed = body.deep_dup
    changed[:essay_grading]['essay'] = 'A different answer.'
    put grading_url(row.id), params: changed, headers: @headers, as: :json
    assert_response :conflict
    assert_equal body[:essay_grading]['essay'], row.reload.essay
    row.destroy!
    assert_equal 0, assignment.reload.number_of_submission
  end

  test 'package opening links the draft; final submission unlocks only the next item' do
    first, second = make_assignment('essay'), make_assignment('essay')
    package = AssignmentPackage.create!(general_user: @user, title: 'Fixture package', status: :active)
    first_item = package.assignment_package_items.create!(essay_assignment: first, position: 1, status: :available)
    second_item = package.assignment_package_items.create!(essay_assignment: second, position: 2, status: :locked)
    post draft_url(second), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
    assert_response :forbidden
    assert_equal 0, second.essay_gradings.count
    post draft_url(first), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
    assert_response :ok
    id = response.parsed_body.dig('essay_grading', 'id')
    assert_equal id, first_item.reload.essay_grading_id
    assert second_item.reload.locked?
    put grading_url(id), params: { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload('essay', 'pending') }, headers: @headers, as: :json
    assert_response :ok
    assert first_item.reload.completed?
    assert second_item.reload.available?
  end

  test 'multipart speaking essay saves then submits the same attachment without duplicate blobs on replay' do
    assignment = make_assignment('speaking_essay')
    post draft_url(assignment), params: { request_id: SecureRandom.uuid }, headers: @headers, as: :json
    id = response.parsed_body.dig('essay_grading', 'id')
    Tempfile.create(['draft-fixture', '.mp3']) do |file|
      file.write('fixture recording'); file.flush
      key = SecureRandom.uuid
      uploaded = Rack::Test::UploadedFile.new(file.path, 'audio/mpeg')
      attrs = { request_id: key, draft_revision: 0, essay_grading: { status: 'draft', essay: 'Audio transcript', file: uploaded } }
      put grading_url(id), params: attrs, headers: @headers
      assert_response :ok, response.body
      row = EssayGrading.find(id)
      blob_id = row.file.blob.id
      put grading_url(id), params: attrs, headers: @headers
      assert_response :ok, response.body
      assert_equal blob_id, row.reload.file.blob.id
      put grading_url(id), params: { request_id: SecureRandom.uuid, draft_revision: 1, essay_grading: { status: 'pending', essay: 'Audio transcript' } }, headers: @headers, as: :json
      assert_response :ok, response.body
      assert_equal blob_id, row.reload.file.blob.id
      refute row.draft?
    end
  end

  test 'legacy Listening request receipt survives deployment and rejects changed answers' do
    assignment = make_assignment('listening')
    attrs = payload('listening', 'pending')
    key = SecureRandom.uuid
    row = EssayGrading.create!(essay_assignment: assignment, general_user: @user, status: :draft)
    row.update_columns(status: EssayGrading.statuses[:graded], meta: {
      'listening_create_request' => { 'key' => key, 'digest' => ListeningSubmissionFingerprint.call(attrs) }
    })
    url = "/api/v1/essay_assignments/#{assignment.code}/essay_gradings.json"
    post url, params: { essay_grading: attrs }, headers: @headers.merge('Idempotency-Key' => key), as: :json
    assert_response :ok, response.body
    assert_equal row.id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal 1, assignment.essay_gradings.count
    post url, params: { essay_grading: attrs.merge('essay' => 'Changed') }, headers: @headers.merge('Idempotency-Key' => key), as: :json
    assert_response :conflict
    assert_equal 1, assignment.essay_gradings.count
  end

  test 'Admin rerun of a prepared draft counts once and rejects a stale student write' do
    assignment = make_assignment('essay')
    row = AssignmentDraftSession.new(assignment: assignment, user: @user).prepare(SecureRandom.uuid)
    2.times { EssayGenerationRun.request_admin_rerun!(row) }
    assert_equal 1, assignment.reload.number_of_submission
    put grading_url(row.id), params: { request_id: SecureRandom.uuid, draft_revision: 0, essay_grading: payload('essay', 'draft') }, headers: @headers, as: :json
    assert_response :conflict
    row.reload.destroy!
    assert_equal 0, assignment.reload.number_of_submission
  end

  private

  def draft_url(assignment) = "/api/v1/essay_assignments/#{assignment.code}/essay_gradings/current_draft"
  def grading_url(id) = "/api/v1/essay_gradings/#{id}.json"

  def make_assignment(category)
    meta = category == 'sentence_puzzle' ? { 'sentence_puzzle' => { 'max_attempts_per_question' => 3, 'questions' => [{ 'id' => 'q1', 'order' => 1, 'correct_sentence' => 'Hello world.', 'blocks' => [{ 'id' => 'a', 'text' => 'Hello', 'order' => 1 }, { 'id' => 'b', 'text' => 'world.', 'order' => 2 }] }] } } : {}
    assignment = EssayAssignment.create!(general_user: @user, category: category, title: 'Draft test', topic: 'Draft test', assignment: 'Draft test', rubric: { 'name' => 'Test' }, meta: meta)
    if category == 'listening'
      quiz = { 'level' => 'A2', 'title' => 'Library', 'instruction' => 'Listen.', 'full_score' => 4,
        'questions' => { 'fill_in_the_blanks' => [], 'multiple_choice' => Array.new(4) { |i| { 'id' => i + 1, 'type' => 'multiple_choice', 'question' => 'Which?', 'answer' => 'A', 'evidence' => ['PRIVATE'], 'options' => { 'A' => 'One', 'B' => 'Two', 'C' => 'Three', 'D' => 'Four' } } } } }
      ListeningAssignmentSnapshot.create!(essay_assignment: assignment, qg_version_id: '123', content_digest: 'a' * 64, level: 'A2', quiz: quiz, plain_transcript: 'PRIVATE', audio_url: 'https://storage.example/audio.wav', audio_metadata: { 'sha256' => 'b' * 64 })
    end
    assignment
  end

  def payload(category, status)
    value = { 'status' => status, 'essay' => 'I am responsible for my homework.', 'using_time' => 12 }
    case category
    when 'comprehension'
      value['grading'] = { 'comprehension' => { 'questions' => [{ 'type' => 'multiple_choice', 'question' => 'Which?', 'answer' => 'A', 'user_answer' => 'A', 'options' => { 'A' => 'One', 'B' => 'Two' } }] } }
    when 'sentence_builder'
      value['sentence_builder'] = [{ 'vocab' => 'responsible', 'sentence' => value['essay'] }]
    when 'sentence_puzzle'
      value['meta'] = { 'sentence_puzzle_attempt' => { 'status' => status == 'draft' ? 'draft' : 'submitted', 'answers' => [] } }
    when 'speaking_pronunciation'
      value['grading'] = { 'speaking_pronunciation_sentences' => [{ 'sentence' => 'Hello', 'result' => { 'pronunciation_accuracy' => 90 } }] }
    when 'listening'
      value['grading'] = { 'listening' => { 'questions' => [{ 'id' => 1, 'user_answer' => 'A' }] } }
    when 'talk_lab_speaking'
      value['meta'] = { 'talk_lab_speaking' => { 'transcript' => value['essay'], 'conversation_id' => 'test-conversation', 'turns' => [{ 'role' => 'student', 'text' => value['essay'] }] } }
    end
    value
  end
end
