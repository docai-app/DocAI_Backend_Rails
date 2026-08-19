# frozen_string_literal: true

require 'test_helper'

class ApiV1EssayOcrTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test 'requires a General User JWT before accepting essay images' do
    host! 'docai.m2mda.com'
    post '/api/v1/essay_ocr', params: { images: [] }, as: :json

    assert_response :unauthorized
  end
end
