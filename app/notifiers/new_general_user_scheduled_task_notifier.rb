# frozen_string_literal: true

# To deliver this notification:
#
# NewGeneralUserScheduledTaskNotifier.with(record: @post, message: "New post").deliver(User.all)

class NewGeneralUserScheduledTaskNotifier < Noticed::Base
  required_params :target_phone_number, :message

  params :target_phone_number, :message
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

  # def deliver(recipients = nil, enqueue_job: true, **options)
  #   validate!

  #   transaction do
  #     recipients_attributes = Array.wrap(recipients).map do |recipient|
  #       recipient_attributes_for(recipient)
  #     end

  #     self.notifications_count = recipients_attributes.size
  #     save!

  #     if Rails.gem_version >= Gem::Version.new("7.0.0.alpha1")
  #       notifications.insert_all!(recipients_attributes, record_timestamps: true) if recipients_attributes.any?
  #     else
  #       time = Time.current
  #       recipients_attributes.each do |attributes|
  #         attributes[:created_at] = time
  #         attributes[:updated_at] = time
  #       end
  #       notifications.insert_all!(recipients_attributes) if recipients_attributes.any?
  #     end
  #   end

  #   binding.pry

  #   # Enqueue delivery job
  #   # EventJob.set(options).perform_later(self) if enqueue_job
  #   Noticed::EventJob.set(options).perform_now(self) if enqueue_job

  #   self
  # end

  # deliver_by :twilio_messaging, format: :format_for_twilio

  # def format_for_twilio
  #   {
  #     Body: params[:message],
  #     From: ENV["TWILIO_PHONE_NUMBER"],
  #     To: params[:target_phone_number]
  #   }
  # end

  deliver_by :twilio_messaging, deliver_now: true do |config|
    config.json = lambda {
      {
        Body: params[:message],
        From: ENV['TWILIO_PHONE_NUMBER'],
        To: params[:target_phone_number]
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

  # deliver_by :twilio_messaging do |config|
  #   config.json = lambda { |params|
  #     {
  #       From: ENV["TWILIO_PHONE_NUMBER"],
  #       To: params[:target_phone_number],
  #       Body: params[:message],
  #     }
  #   }

  #   config.credentials = {
  #     phone_number: ENV["TWILIO_PHONE_NUMBER"],
  #     account_sid: ENV["TWILIO_ACCOUNT_SID"],
  #     auth_token: ENV["TWILIO_AUTH_TOKEN"],
  #   }
  #   # config.credentials = Rails.application.credentials.twilio
  #   # config.phone = "+1234567890"
  #   # config.url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json"
  # end
end
