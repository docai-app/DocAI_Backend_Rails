require 'test_helper'

class Api::V1::UserRecoveryEmailsControllerTest < ActionDispatch::IntegrationTest
  test 'should get update' do
    get api_v1_user_recovery_emails_update_url
    assert_response :success
  end

  test 'should get destroy' do
    get api_v1_user_recovery_emails_destroy_url
    assert_response :success
  end

  test 'should get resend_confirmation' do
    get api_v1_user_recovery_emails_resend_confirmation_url
    assert_response :success
  end
end
