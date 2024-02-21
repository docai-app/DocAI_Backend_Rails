# frozen_string_literal: true

class EmailService
  def self.send_gmail(email, subject, body)
    puts "EmailService: #{email}, #{subject}, #{body}"
    current_user.send_gmail(email, subject, body)
  end
end
