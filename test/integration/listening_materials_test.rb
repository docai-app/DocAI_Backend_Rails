raise 'Isolated Rails DB required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
require 'test_helper'
require 'minitest/mock'

class ListeningMaterialsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    host! 'localhost'
    @teacher = user('teacher')
    @student = user('student')
  end

  test 'anonymous students and teachers without Listening cannot access paid catalog' do
    get '/api/v1/listening_materials'
    assert_response :unauthorized
    [@student, user('teacher', [])].each do |user|
      get '/api/v1/listening_materials', headers: headers(user)
      assert_response :forbidden
      post '/api/v1/essay_assignments', params: { essay_assignment: { category: 'listening', title: 'Forged' } }, headers: headers(user), as: :json
      assert_response :forbidden
      post '/api/v1/listening_materials/123/generate_audio', params: { confirm_paid: true }, headers: headers(user), as: :json
      assert_response :forbidden
    end
  end

  test 'teacher preview strips answer keys and URLs and requires explicit audio confirmation' do
    client = Object.new
    def client.detail(id)
      { 'version_id' => id, 'news_feed_id' => '12', 'level' => 'A2', 'title' => 'Library',
        'plain_transcript' => 'Teacher preview', 'audio_url' => 'PRIVATE_URL',
        'audio' => { 'status' => 'not_generated', 'retryable' => false, 'secret' => 'PRIVATE_KEY' },
        'questions' => [{ 'id' => 1, 'question' => 'Which day?', 'answer' => 'PRIVATE_ANSWER', 'evidence' => 'PRIVATE_EVIDENCE' }] }
    end
    def client.generate_audio(id, retry_failed: false)
      detail(id).merge('audio' => { 'status' => 'queued', 'retryable' => false })
    end
    ListeningQgMaterialClient.stub(:new, client) do
      get '/api/v1/listening_materials/123', headers: headers(@teacher)
      assert_response :success
      assert_equal 'Teacher preview', response.parsed_body.dig('data', 'plain_transcript')
      refute_includes response.body, 'PRIVATE'
      assert_equal 'no-store', response.headers['Cache-Control']
      post '/api/v1/listening_materials/123/generate_audio', params: {}, headers: headers(@teacher), as: :json
      assert_response :unprocessable_entity
      post '/api/v1/listening_materials/123/generate_audio', params: { confirm_paid: true }, headers: headers(@teacher), as: :json
      assert_response :success
      assert_equal 'queued', response.parsed_body.dig('data', 'audio', 'status')
      refute_includes response.body, 'PRIVATE'
    end
  end

  private

  def user(role, features = ['listening'])
    GeneralUser.create!(email: "listening-material-#{SecureRandom.hex(6)}@example.test", password: 'Password123!',
      nickname: role, meta: { 'aienglish_role' => role, 'aienglish_features_list' => features }, konnecai_tokens: {})
  end

  def headers(user)
    token, = Warden::JWTAuth::UserEncoder.new.call(user, :general_user, nil)
    { 'Authorization' => "Bearer #{token}" }
  end
end
