# frozen_string_literal: true

# Use submission attribution first. Legacy records without that snapshot may use
# the assignment's explicit year, never today's teacher/student enrollment.
class CurrentAcademicYearGradings
  YEAR_SQL = 'COALESCE(essay_gradings.submission_academic_year_id, essay_assignments.school_academic_year_id)'.freeze

  def self.call(scope = EssayGrading.all)
    scope.joins(:essay_assignment).where("#{YEAR_SQL} IN (?)", SchoolAcademicYear.active.select(:id))
  end

  def self.unattributed(scope)
    scope.joins(:essay_assignment).where("#{YEAR_SQL} IS NULL")
  end
end
