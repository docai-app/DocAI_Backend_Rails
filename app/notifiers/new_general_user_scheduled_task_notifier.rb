# frozen_string_literal: true

# To deliver this notification:
#
# NewGeneralUserScheduledTaskNotifier.with(record: @post, message: "New post").deliver(User.all)

class NewGeneralUserScheduledTaskNotifier < ApplicationNotifier
  required_params :target_phone_number, :message
  # Add your delivery methods
  #
  # deliver_by :email do |config|
  #   config.mailer = "UserMailer"
  #   config.method = "new_post"
  # end
  #
  # bulk_deliver_by :slack do |config|
  #   config.url = -> { Rails.application.credentials.slack_webhook_url }
  # end
  #
  # deliver_by :custom do |config|
  #   config.class = "MyDeliveryMethod"
  # end

  # Add required params
  #
  # required_param :message

  puts '====== NewGeneralUserScheduledTaskNotifier ====== NewGeneralUserScheduledTaskNotifier'
  puts '====== target_phone_number: target_phone_number ====== message: message'

  deliver_by :twilio_messaging do |config|
    config.json = lambda {
      {
        From: ENV['TWILIO_PHONE_NUMBER'],
        To: :target_phone_number,
        Body: :message
      }
    }

    config.credentials = {
      phone_number: ENV['TWILIO_PHONE_NUMBER'],
      account_sid: ENV['TWILIO_ACCOUNT_SID'],
      auth_token: ENV['TWILIO_AUTH_TOKEN']
    }
    # config.credentials = Rails.application.credentials.twilio
    # config.phone = "+1234567890"
    # config.url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json"
  end
end
