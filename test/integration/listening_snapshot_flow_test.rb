# frozen_string_literal: true

raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'minitest/mock'

class ListeningSnapshotFlowTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    host! 'localhost'
    @teacher = user('teacher')
    @student = user('student')
    @assignment = EssayAssignment.create!(general_user: @teacher, category: 'listening',
      topic: 'Library', assignment: 'Listen and answer.', title: 'Listening test',
      rubric: { 'name' => 'Listening' }, meta: {})
    quiz = { 'level' => 'A2', 'title' => 'Library', 'instruction' => 'Listen.', 'full_score' => 4,
      'questions' => { 'fill_in_the_blanks' => [], 'multiple_choice' => Array.new(4) { |i|
        { 'id' => i + 1, 'type' => 'multiple_choice', 'question' => 'Which day?', 'answer' => 'A',
          'evidence' => ['PRIVATE'], 'options' => { 'A' => 'One', 'B' => 'Two', 'C' => 'Three', 'D' => 'Four' } }
      } } }
    ListeningAssignmentSnapshot.create!(essay_assignment: @assignment, qg_version_id: '123',
      content_digest: 'a' * 64, level: 'A2', quiz: quiz, plain_transcript: 'PRIVATE',
      audio_url: 'https://storage.example/audio.wav', audio_metadata: { 'sha256' => 'b' * 64 })
  end

  test 'owner can read safe content but unrelated student and anonymous cannot' do
    get path, headers: headers(@teacher)
    assert_response :success
    assert_equal 4, response.parsed_body.dig('data', 'questions').length
    refute_includes response.body, 'PRIVATE'
    refute_includes response.body, 'storage.example'
    get path, headers: headers(@student)
    assert_response :forbidden
    get path
    assert_response :unauthorized
  end

  test 'full grading model saves draft and grades against snapshot' do
    grading = EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'draft', grading: { 'listening' => { 'questions' => [{ 'id' => 1, 'user_answer' => 'B', 'answer' => 'B' }] } },
      general_context: {}, revised_essay: {}, meta: {})
    assert_nil grading.reload.score
    refute grading.grading['listening']['questions'][0].key?('is_correct')
    grading.update!(status: 'pending')
    assert_equal 'graded', grading.reload.status
    assert_equal 0, grading.score
    get path, headers: headers(@student)
    assert_response :success
  end

  test 'result view restores snapshot question wording without private answers' do
    grading = EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'pending', grading: { 'listening' => { 'questions' => [{ 'id' => 1, 'user_answer' => 'A' }] } },
      general_context: {}, revised_essay: {}, meta: {})
    get "/api/v1/essay_gradings/#{grading.id}", headers: headers(@student)
    assert_response :success
    rows = response.parsed_body.dig('essay_grading', 'grading', 'listening', 'questions')
    assert_equal 4, rows.size
    assert_equal 'Which day?', rows.first['question']
    assert_equal 'One', rows.first.dig('options', 'A')
    assert_equal 'A', rows.first['user_answer']
    assert_equal true, rows.first['is_correct']
    rows.each { |row| refute row.key?('answer'); refute row.key?('evidence') }
    refute_includes response.body, 'PRIVATE'
    refute_includes response.body, 'storage.example'
    refute grading.reload.grading.dig('listening', 'questions', 0).key?('question')
  end

  test 'submitted play count comes from server state and remains stable' do
    playback = ListeningPlaybackState.create!(essay_assignment: @assignment, general_user: @student, play_count: 2)
    grading = EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'draft', grading: { 'listening' => { 'play_count' => 999, 'questions' => [] } },
      general_context: {}, revised_essay: {}, meta: {})
    refute grading.grading['listening'].key?('play_count')
    grading.update!(status: 'pending')
    assert_equal 2, grading.reload.grading.dig('listening', 'play_count')
    playback.update!(play_count: 3)
    grading.update!(grading: { 'listening' => { 'play_count' => 999, 'questions' => [] } })
    assert_equal 2, grading.reload.grading.dig('listening', 'play_count')
  end

  test 'submission API enforces access and ignores forged score and answers' do
    submission_path = "/api/v1/essay_assignments/#{@assignment.code}/essay_gradings"
    payload = { essay_grading: { status: 'pending', grading: { listening: {
      score: 999, full_score: 999, questions: [{ id: 1, user_answer: 'B', answer: 'B', is_correct: true }]
    } } } }
    post submission_path, params: payload, headers: headers(@student), as: :json
    assert_response :forbidden
    assert_equal 0, @assignment.essay_gradings.count
    # Establish historical draft access using the real model; distribution API
    # and code-join onboarding are separate integration scenarios.
    EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'draft', grading: {}, general_context: {}, revised_essay: {}, meta: {})
    post submission_path, params: payload, headers: headers(@student), as: :json
    assert_response :created
    result = response.parsed_body.fetch('essay_grading')
    assert_equal 'graded', result['status']
    assert_equal 0, result.dig('grading', 'listening', 'score')
    assert_equal 4, result.dig('grading', 'listening', 'full_score')
    refute result.dig('grading', 'listening', 'questions', 0).key?('answer')
  end

  test 'listening create request retries reuse a record and reject changed payloads' do
    submission_path = "/api/v1/essay_assignments/#{@assignment.code}/essay_gradings"
    request_headers = headers(@teacher).merge('Idempotency-Key' => 'listening-create-request-0001')
    payload = { essay_grading: { status: 'draft', using_time: 12,
      grading: { listening: { questions: [{ id: 1, user_answer: 'B' }] } } } }
    post submission_path, params: payload, headers: request_headers, as: :json
    assert_response :created
    original_id = response.parsed_body.dig('essay_grading', 'id')
    post submission_path, params: payload, headers: request_headers, as: :json
    assert_response :ok
    assert_equal original_id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal 1, @assignment.essay_gradings.count
    grading = EssayGrading.find(original_id)
    receipt = grading.meta.fetch('listening_create_request')
    grading.update!(meta: {})
    assert_equal receipt, grading.reload.meta.fetch('listening_create_request')
    payload[:essay_grading][:grading][:listening][:questions][0][:user_answer] = 'A'
    post submission_path, params: payload, headers: request_headers, as: :json
    assert_response :conflict
    assert_equal 1, @assignment.essay_gradings.count
    assert_equal 'B', grading.reload.grading.dig('listening', 'questions', 0, 'user_answer')
    payload[:essay_grading][:status] = 'pending'
    final_headers = headers(@teacher).merge('Idempotency-Key' => 'listening-final-request-0001')
    post submission_path, params: payload, headers: final_headers, as: :json
    assert_response :created
    final_id = response.parsed_body.dig('essay_grading', 'id')
    assert_equal 'graded', response.parsed_body.dig('essay_grading', 'status')
    post submission_path, params: payload, headers: final_headers, as: :json
    assert_response :ok
    assert_equal final_id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal 2, @assignment.essay_gradings.count
    post submission_path, params: payload, headers: headers(@student).merge('Idempotency-Key' => 'listening-create-request-0001'), as: :json
    assert_response :forbidden
  end

  test 'teacher creation API persists trusted snapshot without exposing answers' do
    school = School.create!(name: 'Listening test school', code: "listen-#{SecureRandom.hex(4)}", timezone: 'Asia/Hong_Kong', meta: {})
    year = SchoolAcademicYear.create!(school: school, name: 'Listening test year',
      start_date: Date.current.beginning_of_year, end_date: Date.current.end_of_year, status: :active, meta: {})
    TeacherAssignment.create!(general_user: @teacher, school_academic_year: year,
      department: 'English', position: 'Teacher', status: :active, meta: {})
    snapshot = @assignment.listening_assignment_snapshot
    attributes = snapshot.attributes.slice('qg_version_id', 'content_digest', 'level', 'quiz',
      'plain_transcript', 'audio_url', 'audio_metadata').symbolize_keys
    client = Minitest::Mock.new
    client.expect(:fetch, attributes, version_id: '123', news_feed_id: '34', level: 'A2')
    ListeningQgVersionClient.stub(:new, client) do
      post '/api/v1/essay_assignments', headers: headers(@teacher), as: :json, params: {
        essay_assignment: { category: 'listening', topic: 'Library', title: 'API Listening',
          assignment: 'Listen.', rubric: { name: 'Listening' }, school_academic_year_id: year.id,
          meta: { listening: { version_id: '123', news_feed_id: '34', level: 'A2',
            play_limit: 2, questions: ['FORGED'], transcript: 'FORGED' } } }
      }
    end
    assert_response :created
    client.verify
    result = response.parsed_body.fetch('essay_assignment')
    created = EssayAssignment.find(result['id'])
    assert_equal @teacher.id, created.general_user_id
    assert_equal year.id, created.school_academic_year_id
    assert_equal snapshot.quiz, created.listening_assignment_snapshot.quiz
    refute_includes response.body, 'PRIVATE'
    refute_includes response.body, 'FORGED'
    refute_includes response.body, 'storage.example'
    StudentEnrollment.create!(general_user: @student, school_academic_year: year,
      class_name: 'A1', class_number: '1', status: :active, meta: {})
    post "/api/v1/essay_assignments/#{created.id}/distributions", headers: headers(@teacher), as: :json,
      params: { distribution: { distribution_type: 'individual', target_student_id: @student.id,
        deadline: 1.week.from_now.iso8601 } }
    assert_response :created
    assert created.assigned_to_student?(@student)
    get "/api/v1/essay_assignments/#{created.id}/listening_content", headers: headers(@student)
    assert_response :success
    audio_reader = Object.new
    audio_reader.define_singleton_method(:read) { |_| 'distributed-student-audio' }
    ListeningAudioReader.stub(:new, audio_reader) do
      post "/api/v1/essay_assignments/#{created.id}/listening_audio", headers: headers(@student), as: :json,
        params: { request_id: 'distributed-student-play-1' }
      assert_response :success
      assert_equal 'distributed-student-audio', response.body
      assert_equal 1, ListeningPlaybackState.find_by!(essay_assignment: created, general_user: @student).play_count
    end
    post "/api/v1/essay_assignments/#{created.code}/essay_gradings", headers: headers(@student), as: :json,
      params: { essay_grading: { status: 'pending', grading: { listening: {
        questions: [{ id: 1, user_answer: 'A' }]
      } } } }
    assert_response :created
    assert_equal 1, response.parsed_body.dig('essay_grading', 'grading', 'listening', 'score')
  end

  test 'draft PATCH is authorized and final submission cannot be rewritten or reopened' do
    grading = EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'draft', grading: {}, general_context: {}, revised_essay: {}, meta: {})
    url = "/api/v1/essay_gradings/#{grading.id}"
    payload = { essay_grading: { status: 'draft', grading: { listening: {
      questions: [{ id: 1, user_answer: 'A' }]
    } } } }
    patch url, params: payload, headers: headers(user('student')), as: :json
    assert_response :forbidden
    patch url, params: payload, headers: headers(@student), as: :json
    assert_response :success
    assert_nil grading.reload.score
    patch url, params: { essay_grading: { status: 'pending' } }, headers: headers(@student), as: :json
    assert_response :success
    assert_equal 'graded', grading.reload.status
    assert_equal 1, grading.score
    before = grading.attributes
    patch url, params: payload, headers: headers(@student), as: :json
    assert_response :unprocessable_entity
    assert_equal before, grading.reload.attributes
  end

  test 'audio endpoint checks authorization counts issues and safely retries' do
    # Set the fixture's initial policy without exercising the separate settings guard.
    @assignment.update_columns(meta: { 'listening' => { 'play_limit' => 1 } })
    url = "/api/v1/essay_assignments/#{@assignment.id}/listening_audio"
    payload = { request_id: 'playback-request-0001' }
    reader = Object.new
    reader.define_singleton_method(:read) { |_| 'test-audio-bytes' }
    ListeningAudioReader.stub(:new, reader) do
      post url, params: payload, as: :json
      assert_response :unauthorized
      post url, params: payload, headers: headers(@student), as: :json
      assert_response :forbidden
      assert_equal 0, ListeningPlaybackState.where(essay_assignment: @assignment).count
      post url, params: payload, headers: headers(@teacher), as: :json
      assert_response :success
      assert_equal 'test-audio-bytes', response.body
      assert_equal 'audio/wav', response.media_type
      assert_includes response.headers['Cache-Control'], 'no-store'
      assert_equal '1', response.headers['X-Listening-Play-Count']
      post url, params: payload, headers: headers(@teacher), as: :json
      assert_response :success
      assert_equal 1, ListeningPlaybackState.find_by!(essay_assignment: @assignment, general_user: @teacher).play_count
      get path, headers: headers(@teacher)
      assert_response :success
      assert_equal 1, response.parsed_body.dig('data', 'playback', 'play_count')
      assert_equal 1, response.parsed_body.dig('data', 'playback', 'play_limit')
      refute_includes response.body, 'last_request_id'
      post url, params: { request_id: 'playback-request-0002' }, headers: headers(@teacher), as: :json
      assert_response :forbidden
      assert_equal 1, ListeningPlaybackState.find_by!(essay_assignment: @assignment, general_user: @teacher).play_count
    end
  end

  test 'audio storage failure does not consume playback allowance' do
    reader = Object.new
    reader.define_singleton_method(:read) { |_| raise ListeningAudioReader::Unavailable }
    ListeningAudioReader.stub(:new, reader) do
      post "/api/v1/essay_assignments/#{@assignment.id}/listening_audio",
        params: { request_id: 'playback-request-fail' }, headers: headers(@teacher), as: :json
      assert_response :service_unavailable
      assert_equal 0, ListeningPlaybackState.find_by!(essay_assignment: @assignment, general_user: @teacher).play_count
    end
  end

  test 'listening draft recovery is scoped to the current user and contains only responses' do
    draft = EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
      status: 'draft', grading: { 'listening' => { 'questions' => [{ 'id' => 1, 'user_answer' => 'B' }] } },
      general_context: {}, revised_essay: {}, meta: {})
    url = "/api/v1/essay_assignments/#{@assignment.code}/essay_gradings/current_draft"
    get url, headers: headers(@student)
    assert_response :success
    assert_equal draft.id, response.parsed_body.dig('essay_grading', 'id')
    assert_equal (1..4).map { |id| { 'id' => id, 'user_answer' => id == 1 ? 'B' : nil } },
      response.parsed_body.dig('essay_grading', 'grading', 'listening', 'questions')
    refute_includes response.body, 'PRIVATE'
    get url, headers: headers(@teacher)
    assert_response :success
    assert_nil response.parsed_body['essay_grading']
    get url, headers: headers(user('student'))
    assert_response :forbidden
  end

  # Opt-in network test: reads one existing fixture; never creates Azure data.
  if ENV['LISTENING_LIVE_AUDIO_READ'] == '1'
    test 'live Azure bytes pass through the authorized student audio endpoint' do
      assert_equal 'listening_rails_isolated_test', ActiveRecord::Base.connection.current_database
      audio = File.binread(ENV.fetch('LISTENING_AUDIO_FIXTURE'))
      ssml = File.binread(ENV.fetch('LISTENING_SSML_FIXTURE'))
      key = "listening/azure/#{Digest::SHA256.hexdigest(ssml)}/riff-24khz-16bit-mono-pcm.wav"
      account = ENV.fetch('AZURE_STORAGE_NAME')
      container = ENV.fetch('QG_LISTENING_STORAGE_CONTAINER')
      # Only changes the transaction-scoped fixture; model snapshot immutability
      # remains enforced for product writes.
      @assignment.listening_assignment_snapshot.update_columns(
        audio_url: "https://#{account}.blob.core.windows.net/#{container}/#{key}",
        audio_metadata: { 'storage_key' => key, 'byte_size' => audio.bytesize,
          'sha256' => Digest::SHA256.hexdigest(audio) })
      EssayGrading.create!(essay_assignment: @assignment, general_user: @student,
        status: 'draft', grading: {}, general_context: {}, revised_essay: {}, meta: {})
      post "/api/v1/essay_assignments/#{@assignment.id}/listening_audio", headers: headers(@student),
        params: { request_id: 'live-azure-student-play-1' }, as: :json
      assert_response :success
      assert_equal 'audio/wav', response.media_type
      assert_equal audio.bytesize, response.body.bytesize
      assert_equal Digest::SHA256.hexdigest(audio), Digest::SHA256.hexdigest(response.body)
      assert_equal '1', response.headers['X-Listening-Play-Count']
      assert_includes response.headers['Cache-Control'], 'no-store'
      assert_nil response.headers['Location']
      assert_equal 1, ListeningPlaybackState.find_by!(essay_assignment: @assignment, general_user: @student).play_count
    end
  end

  private


  def user(role)
    GeneralUser.create!(email: "listening-#{SecureRandom.hex(6)}@example.test", password: 'Password123!',
      nickname: role, meta: { 'aienglish_role' => role, 'aienglish_features_list' => ['listening'] }, konnecai_tokens: {})
  end

  def headers(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    { 'Authorization' => "Bearer #{token}" }
  end

  def path
    "/api/v1/essay_assignments/#{@assignment.id}/listening_content"
  end
end
