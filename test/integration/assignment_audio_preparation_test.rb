# frozen_string_literal: true
raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'minitest/mock'
require 'timeout'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class AssignmentAudioPreparationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  self.use_transactional_tests = false
  parallelize(workers: 1)

  setup do
    host! 'localhost'
    @users = []
    @user = new_user
    @assignment = EssayAssignment.create!(general_user: @user, category: 'speaking_conversation',
      title: 'Audio concurrency fixture', topic: 'Audio', assignment: 'Audio', rubric: { 'name' => 'Test' },
      meta: { 'speaking_conversation' => { 'mode' => 'preset_questions', 'questions' => [{ 'id' => 'q1', 'text' => 'Introduce yourself.', 'order' => 1 }] } })
    @draft = session_for(@user).prepare(SecureRandom.uuid)
    token, = Warden::JWTAuth::UserEncoder.new.call(@user, :general_user, nil)
    @headers = { 'Authorization' => "Bearer #{token}" }
    @body = { request_id: SecureRandom.uuid, draft_revision: 0,
      answer: { answer_text: 'My name is Alex.', question_order: 1, answer_audio_base64: 'data:audio/mpeg;base64,YXVkaW8=' } }
  end

  teardown do
    @assignment.essay_gradings.destroy_all
    @assignment.destroy!
    GeneralUser.where(id: @users.map(&:id)).delete_all
  end

  test 'HTTP audio save releases the connection and an exact replay skips upload' do
    calls = 0
    uploader = ->(**_) {
      calls += 1
      assert_not ActiveRecord::Base.connection_pool.active_connection?, 'no DB checkout during upload'
      'https://storage.example/audio.mp3'
    }
    SpeakingConversationAudioStorageService.stub(:upload!, uploader) do
      2.times { save_answer; assert_response :ok, response.body }
      changed = @body.deep_dup
      changed[:answer][:answer_text] = 'Changed under the same request key'
      patch answer_url, params: changed, headers: @headers, as: :json
      assert_response :conflict
    end
    assert_equal 1, calls
    assert_equal 1, @draft.reload.meta.dig('assignment_draft_session', 'revision')
    assert_equal 'https://storage.example/audio.mp3', @draft.grading.dig('speaking_conversation', 'answers', 0, 'answer_audio_url')
    refute @draft.grading.to_json.include?('base64')
  end

  test 'unconfirmed upload does not advance revision or silently drop audio' do
    SpeakingConversationAudioStorageService.stub(:upload!, nil) do
      save_answer
      assert_response :internal_server_error
    end
    assert_equal 0, @draft.reload.meta.dig('assignment_draft_session', 'revision')
    assert_empty Array(@draft.grading.dig('speaking_conversation', 'answers'))
    SpeakingConversationAudioStorageService.stub(:upload!, 'https://storage.example/retry.mp3') do
      save_answer
      assert_response :ok
    end
    assert_equal 1, @draft.reload.meta.dig('assignment_draft_session', 'revision')
  end

  test 'a concurrent newer save wins while the old audio upload is outside the lock' do
    uploader = ->(**_) {
      session_for(@user).write({ 'essay' => 'Newer saved work' }, row: @draft,
        request_id: SecureRandom.uuid, revision: 0) { |row| row.essay = 'Newer saved work' }
      'https://storage.example/stale.mp3'
    }
    SpeakingConversationAudioStorageService.stub(:upload!, uploader) do
      save_answer
      assert_response :conflict
    end
    assert_equal 'Newer saved work', @draft.reload.essay
    assert_equal 1, @draft.meta.dig('assignment_draft_session', 'revision')
    assert_empty Array(@draft.grading.dig('speaking_conversation', 'answers'))
  end

  test 'storage fallback uploads file bytes without retaining its metadata connection' do
    ActiveStorage::Current.url_options = { host: 'http://localhost' }
    storage = ActiveStorage::Blob.services.fetch('test')
    upload = storage.method(:upload)
    observed = false
    filename = "audio-fallback-#{SecureRandom.hex(8)}.mp3"
    ActiveRecord::Base.connection_pool.release_connection
    ApplicationRecord.stub(:preferred_microsoft_storage_service, :test) do
      storage.stub(:upload, ->(key, io, **options) {
        observed = true
        assert_not ActiveRecord::Base.connection_pool.active_connection?
        upload.call(key, io, **options)
      }) do
        url = SpeakingConversationAudioStorageService.send(:upload_with_active_storage!, 'audio bytes', filename, 'audio/mpeg')
        assert_match %r{http://localhost}, url
      end
    end
    assert observed
    blob = ActiveStorage::Blob.find_by!(filename: filename)
    assert_equal 'audio bytes', blob.download
  ensure
    ActiveStorage::Blob.where(filename: filename).each(&:purge) if filename
  end

  test 'a new checkout restores the request search path before committing' do
    pool = ActiveRecord::Base.connection_pool
    original = pool.connection.schema_search_path
    expected = 'public, pg_catalog'
    pool.connection.schema_search_path = expected
    session_for(@user).write({ 'essay' => 'Tenant-safe' }, row: @draft, request_id: SecureRandom.uuid,
      revision: 0, prepare: -> {
        pool.connection.schema_search_path = 'pg_catalog, public'
        pool.release_connection
        true
      }) { |row| assert_equal expected, pool.connection.schema_search_path; row.essay = 'Tenant-safe' }
  ensure
    pool.connection.schema_search_path = original if original
  end

  test 'more simultaneous slow uploads than pool slots do not exhaust the database pool' do
    pool = ActiveRecord::Base.connection_pool
    count = pool.size + 1
    rows = count.times.map do
      user = new_user
      [user, session_for(user).prepare(SecureRandom.uuid)]
    end
    ready, go = Queue.new, Queue.new
    threads = rows.map do |user, draft|
      Thread.new do
        session_for(user).write({ 'essay' => 'Saved audio' }, row: draft, request_id: SecureRandom.uuid,
          revision: 0, prepare: -> {
            leased = !!pool.active_connection?
            ready << leased
            go.pop
            'https://storage.example/audio.mp3'
          }) { |row, url| row.essay = url }.id
      ensure
        pool.release_connection
      end
    end
    leases = Timeout.timeout(10) { count.times.map { ready.pop } }
    assert_equal [false] * count, leases
    # A database-backed page can still read while every simulated upload waits.
    assert_equal count + 1, EssayGrading.where(essay_assignment: @assignment).count
    count.times { go << true }
    ids = Timeout.timeout(10) { threads.map(&:value) }
    assert_equal count, ids.uniq.length
    assert_equal [1], EssayGrading.where(id: ids).map { |g| g.meta.dig('assignment_draft_session', 'revision') }.uniq
  ensure
    count&.times { go << true } if go
    threads&.each { |thread| thread.join(5) || thread.kill }
  end

  private

  def new_user
    user = GeneralUser.create!(email: "audio-#{SecureRandom.hex(8)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @users << user
    user
  end

  def session_for(user)
    AssignmentDraftSession.new(assignment: @assignment, user: user)
  end

  def answer_url
    "/api/v1/essay_gradings/#{@draft.id}/speaking_conversation/answers/q1"
  end

  def save_answer
    patch answer_url, params: @body, headers: @headers, as: :json
  end
end
