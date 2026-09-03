# frozen_string_literal: true

# Adds an explicit academic-year reference and safely backfills unambiguous legacy rows.
class AddSchoolAcademicYearToEssayAssignments < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  class EssayAssignmentRecord < ActiveRecord::Base # :nodoc:
    self.table_name = 'essay_assignments'
  end

  class TeacherAssignmentRecord < ActiveRecord::Base # :nodoc:
    self.table_name = 'teacher_assignments'
  end

  def up
    unless column_exists?(:essay_assignments, :school_academic_year_id)
      add_column :essay_assignments, :school_academic_year_id, :uuid
    end

    unless index_exists?(:essay_assignments, :school_academic_year_id)
      add_index :essay_assignments, :school_academic_year_id, algorithm: :concurrently
    end

    unless foreign_key_exists?(:essay_assignments, :school_academic_years)
      add_foreign_key :essay_assignments, :school_academic_years, validate: false
      validate_foreign_key :essay_assignments, :school_academic_years
    end

    backfill_school_academic_years!
  end

  def down
    if foreign_key_exists?(:essay_assignments, :school_academic_years)
      remove_foreign_key :essay_assignments, :school_academic_years
    end
    if index_exists?(:essay_assignments, :school_academic_year_id)
      remove_index :essay_assignments, :school_academic_year_id, algorithm: :concurrently
    end
    if column_exists?(:essay_assignments, :school_academic_year_id)
      remove_column :essay_assignments, :school_academic_year_id
    end
  end

  private

  def backfill_school_academic_years!
    years_by_teacher_id = {}
    backfilled_count = 0
    unresolved_count = 0

    EssayAssignmentRecord.where(school_academic_year_id: nil).find_each do |assignment|
      academic_years = years_by_teacher_id.fetch(assignment.general_user_id) do |teacher_id|
        years_by_teacher_id[teacher_id] = academic_years_for(teacher_id)
      end
      academic_year = uniquely_matching_academic_year(assignment.created_at, academic_years)

      if academic_year
        assignment.update_columns(school_academic_year_id: academic_year.fetch(:id))
        backfilled_count += 1
      else
        unresolved_count += 1
      end
    end

    say "Backfilled #{backfilled_count} essay assignments; #{unresolved_count} require legacy date fallback"
  end

  def academic_years_for(teacher_id)
    return [] if teacher_id.blank?

    TeacherAssignmentRecord
      .joins(<<~SQL.squish)
        INNER JOIN school_academic_years
          ON school_academic_years.id = teacher_assignments.school_academic_year_id
        LEFT JOIN schools
          ON schools.id = school_academic_years.school_id
      SQL
      .where(general_user_id: teacher_id)
      .pluck(
        'school_academic_years.id',
        'school_academic_years.start_date',
        'school_academic_years.end_date',
        'school_academic_years.status',
        'schools.timezone'
      )
      .map do |id, start_date, end_date, status, timezone|
        {
          id:,
          start_date:,
          end_date:,
          status:,
          time_zone: ActiveSupport::TimeZone[timezone.presence] ||
                     Time.zone ||
                     ActiveSupport::TimeZone['UTC']
        }
      end
  end

  def uniquely_matching_academic_year(created_at, academic_years)
    matches = academic_years.select do |academic_year|
      local_date = created_at.in_time_zone(academic_year.fetch(:time_zone)).to_date
      academic_year.fetch(:start_date) <= local_date && local_date <= academic_year.fetch(:end_date)
    end

    return matches.first if matches.one?

    active_matches = matches.select { |academic_year| academic_year.fetch(:status).to_i == 1 }
    active_matches.one? ? active_matches.first : nil
  end
end
