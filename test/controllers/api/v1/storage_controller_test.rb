# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class StorageControllerTest < ActionDispatch::IntegrationTest
      test 'should get –no-assets' do
        get api_v1_storage_–no - assets_url
        assert_response :success
      end
    end
  end
end
