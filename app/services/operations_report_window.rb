# Reports always use Macau civil time, independently of the host timezone.
class OperationsReportWindow
  ZONE = ActiveSupport::TimeZone['Asia/Macau']

  def self.latest_end(now = Time.current)
    local = now.in_time_zone(ZONE)
    local.beginning_of_day + (local.hour >= 18 ? 18 : local.hour >= 12 ? 12 : 0).hours
  end

  def self.start_for(ending)
    time = ending.in_time_zone(ZONE)
    raise ArgumentError, 'Not a report boundary' unless [0, 12, 18].include?(time.hour) && time.min.zero? && time.sec.zero?
    time - (time.hour == 12 ? 12 : 6).hours
  end

  def self.due_ends(since:, now: Time.current)
    result = []
    ending = latest_end(now)
    # Do not flood the mailbox after a prolonged outage; the report flags this.
    floor = [since, now - 7.days].max
    while ending >= floor
      result.unshift(ending)
      ending = start_for(ending)
    end
    result
  end
end
