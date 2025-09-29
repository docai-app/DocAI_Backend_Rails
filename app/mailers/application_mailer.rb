# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_FROM', '"AI English Support" <aienglish-support@docai.net>')
  layout 'mailer'
end
