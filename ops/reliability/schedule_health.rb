# Rails runner, read-only unless operator passes --notify; payload is issue codes.
if ARGV == ['--notify']
  codes = JSON.parse(STDIN.read)
  raise 'Invalid health alert' unless codes.is_a?(Array) && codes.size <= 20 &&
    codes.all? { |code| code.is_a?(String) && code.match?(/\A[a-z_:]+\z/) }
  AdminNotificationMailer.reliability_health_alert(codes).deliver_now
  puts 'SMTP_ACCEPTED'
else
  puts "SCHEDULE_HEALTH=#{JSON.generate(ReliabilityScheduleHealth.call)}"
end
