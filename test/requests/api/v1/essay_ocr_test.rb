# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class ApiV1EssayOcrTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    host! 'docai.m2mda.com'
    @user = GeneralUser.create!(
      email: "essay-ocr-#{SecureRandom.hex(5)}@example.test",
      password: 'Password123!',
      nickname: 'Essay OCR Learner',
      meta: {
        'aienglish_role' => 'student',
        'aienglish_features_list' => ['essay']
      },
      konnecai_tokens: {}
    )
  end

  test 'requires a General User JWT before accepting essay images' do
    post '/api/v1/essay_ocr', params: { images: [] }, as: :json

    assert_response :unauthorized
  end

  test 'rejects an authenticated account without the Essay feature' do
    @user.update!(meta: @user.meta.merge('aienglish_features_list' => ['comprehension']))

    post '/api/v1/essay_ocr',
         params: { images: [] },
         headers: { 'Authorization' => sign_in_token },
         as: :json

    assert_response :forbidden
    assert_equal 'ESSAY_OCR_FORBIDDEN', JSON.parse(response.body)['error_code']
  end

  test 'returns OCR text for an authenticated Essay learner' do
    service = Struct.new(:model) do
      def call(images:)
        raise 'images were not forwarded' unless images.present?

        'Original learner essay.'
      end
    end.new('kimi-k2.6')
    limiter = Object.new
    limiter.define_singleton_method(:check!) { |user_id:, ip:| user_id.present? && ip.present? }

    service_factory = ->(**_options) { service }
    EssayOcr::MoonshotService.stub(:new, service_factory) do
      EssayOcr::RateLimiter.stub(:new, limiter) do
        post '/api/v1/essay_ocr',
             params: { images: [{ dataUrl: 'data:image/png;base64,test-stub' }] },
             headers: { 'Authorization' => sign_in_token },
             as: :json
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'kimi-k2.6', body['model']
    assert_equal 'Original learner essay.', body['text']
  end

  private

  def sign_in_token
    post '/general_users/sign_in',
         params: { general_user: { email: @user.email, password: 'Password123!' } },
         as: :json
    response.headers['Authorization'].to_s.tap { |token| assert token.present? }
  end
end
