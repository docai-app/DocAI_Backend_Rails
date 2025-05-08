require 'test_helper'

class RecoveryEmailMailerTest < ActionMailer::TestCase
  test 'confirmation_instructions' do
    mail = RecoveryEmailMailer.confirmation_instructions
    assert_equal 'Confirmation instructions', mail.subject
    assert_equal ['to@example.org'], mail.to
    assert_equal ['from@example.com'], mail.from
    assert_match 'Hi', mail.body.encoded
  end
end
