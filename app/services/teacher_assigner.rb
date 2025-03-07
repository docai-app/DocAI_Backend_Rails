class TeacherAssigner
  include ActiveModel::Model

  attr_reader :assigned_count, :skipped_count
  attr_accessor :school, :academic_year_name, :email_patterns,
                :department, :position

  validates :school, :academic_year_name, :email_patterns,
            :department, :position, presence: true

  def assign
    return false unless valid?

    @assigned_count = 0
    @skipped_count = 0

    ActiveRecord::Base.transaction do
      process_patterns
      true
    rescue StandardError => e
      errors.add(:base, e.message)
      false
    end
  end

  private

  def process_patterns
    patterns = email_patterns.split(';').map(&:strip)
    academic_year = find_academic_year

    patterns.each do |pattern|
      process_single_pattern(pattern, academic_year)
    end
  end

  # ... 其他輔助方法 ...
end
