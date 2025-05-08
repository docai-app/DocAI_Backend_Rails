# Preview all emails at http://localhost:3000/rails/mailers/recovery_email_mailer
class RecoveryEmailMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/recovery_email_mailer/confirmation_instructions
  def confirmation_instructions
    RecoveryEmailMailer.confirmation_instructions
  end
end
