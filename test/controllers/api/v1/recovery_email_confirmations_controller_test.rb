require 'test_helper'

class Api::V1::RecoveryEmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  test 'should get show' do
    get api_v1_recovery_email_confirmations_show_url
    assert_response :success
  end
end
