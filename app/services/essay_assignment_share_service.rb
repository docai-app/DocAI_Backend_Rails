# frozen_string_literal: true

class EssayAssignmentShareService
  class ShareError < StandardError
    attr_reader :details

    def initialize(message, details: nil)
      super(message)
      @details = details
    end
  end

  class Result
    attr_reader :shared_teachers, :errors

    def initialize(shared_teachers:, errors: [])
      @shared_teachers = shared_teachers
      @errors = errors
    end

    def success?
      errors.empty?
    end
  end

  TEACHER_ROLE = 'teacher'
  INELIGIBLE_MISSING_CATEGORY = 'missing_category_permission'

  def self.sync_shares!(assignment:, actor:, teacher_ids:)
    new(assignment: assignment, actor: actor).sync_shares!(teacher_ids: teacher_ids)
  end

  def self.school_teacher_candidates(school:, exclude_user:)
    new(assignment: nil, actor: exclude_user).school_teacher_candidates(school: school)
  end

  def initialize(assignment:, actor:)
    @assignment = assignment
    @actor = actor
  end

  def sync_shares!(teacher_ids:)
    authorize_owner!
    school = actor_school!

    normalized_ids = normalize_teacher_ids(teacher_ids)
    active_shares = @assignment.essay_assignment_shares.active.index_by(&:shared_with_general_user_id)
    validation_errors = validate_recipient_ids(normalized_ids, school, retained_ids: active_shares.keys)
    raise ShareError.new('Invalid share recipients', details: validation_errors) if validation_errors.any?

    desired_ids = normalized_ids.to_set

    EssayAssignmentShare.transaction do
      active_shares.each do |teacher_id, share|
        next if desired_ids.include?(teacher_id)

        share.revoke!
      end

      normalized_ids.each do |teacher_id|
        existing = @assignment.essay_assignment_shares.find_by(shared_with_general_user_id: teacher_id)
        if existing&.active?
          next
        elsif existing&.revoked?
          existing.reactivate!(shared_by: @actor)
        else
          create_share!(teacher_id: teacher_id, school: school)
        end
      end
    end

    # EssayAssignmentShareNotificationJob.perform_async(share.id) # reserved for Phase 2+

    Result.new(shared_teachers: active_shared_teacher_payloads)
  end

  def school_teacher_candidates(school:)
    raise ShareError, 'School is required' if school.blank?

    assignments = self.class.current_school_teacher_assignments(school: school)
    assignments = assignments.where.not(general_user_id: @actor.id) if @actor&.id
    # Fetch only the five displayed fields, without loading full accounts or
    # querying each teacher's profile separately.
    rows = assignments
           .order(Arel.sql('LOWER(COALESCE(general_users.nickname, general_users.email)) ASC'))
           .pluck('general_users.id', 'general_users.email', 'general_users.nickname',
                  'teacher_assignments.department', 'teacher_assignments.position')
    teacher_rows = rows.map do |id, email, nickname, department, position|
      {
        id: id,
        email: email,
        nickname: nickname,
        department: department,
        position: position
      }
    end

    {
      teachers: teacher_rows,
      departments: teacher_rows.map { |row| row[:department] }.reject(&:blank?).uniq.sort
    }
  end

  def self.school_teachers_relation(school:, exclude_user_id: nil)
    teacher_ids = current_school_teacher_assignments(school: school).select(:general_user_id)
    teachers = GeneralUser.where(id: teacher_ids).where(locked_at: nil)
    teachers = teachers.where.not(id: exclude_user_id) if exclude_user_id.present?
    teachers.order(Arel.sql('LOWER(COALESCE(general_users.nickname, general_users.email)) ASC'))
  end

  def self.current_school_teacher_assignments(school:)
    year = school.current_academic_year
    return TeacherAssignment.none unless year

    TeacherAssignment
      .joins(:general_user)
      .where(school_academic_year_id: year.id, status: TeacherAssignment.statuses[:active])
      .where(general_users: { locked_at: nil })
      .where("general_users.meta->>'aienglish_role' = ?", TEACHER_ROLE)
  end

  # Historical membership is still used by existing assignment access checks.
  # New sharing uses the narrower current_school_teacher_assignments scope.
  def self.school_teacher_ids(school:)
    via_assignment = TeacherAssignment
                     .joins(:school_academic_year, :general_user)
                     .where(school_academic_years: { school_id: school.id })
                     .where(status: TeacherAssignment.statuses[:active])
                     .where("general_users.meta->>'aienglish_role' = ?", TEACHER_ROLE)
                     .distinct
                     .pluck(:general_user_id)

    via_school_id = GeneralUser
                    .where(school_id: school.id)
                    .where("meta->>'aienglish_role' = ?", TEACHER_ROLE)
                    .pluck(:id)

    (via_assignment + via_school_id).uniq
  end

  def self.departments_for_school(school)
    current_school_teacher_assignments(school: school)
      .where.not(department: [nil, ''])
      .distinct
      .order(:department)
      .pluck(:department)
  end

  def self.school_for_teacher(teacher)
    return nil if teacher.blank?

    current_assignment = teacher.current_teaching_assignment
    return current_assignment.school_academic_year.school if current_assignment.present?

    teacher.get_school
  end

  def self.same_school_teacher?(school:, teacher:)
    return false if school.blank? || teacher.blank?
    return false unless teacher.aienglish_role == TEACHER_ROLE

    school_teacher_ids(school: school).include?(teacher.id)
  end

  private

  def authorize_owner!
    return if @actor&.aienglish_global_admin?
    return if @assignment.owned_by?(@actor)

    raise ShareError, 'Only the assignment owner can manage shares'
  end

  def actor_school!
    if @actor&.aienglish_global_admin?
      school = @assignment&.school_academic_year&.school
      school ||= @assignment&.assignment_distributions
                           &.where.not(school_id: nil)
                           &.order(created_at: :desc)
                           &.first
                           &.school
      return school if school.present?

      raise ShareError, 'Assignment school context is required'
    end

    school = self.class.school_for_teacher(@actor)
    raise ShareError, 'School context is required' if school.blank?

    school
  end

  def normalize_teacher_ids(teacher_ids)
    Array(teacher_ids).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  def validate_recipient_ids(teacher_ids, school, retained_ids: [])
    errors = []
    assignment_category = @assignment.category
    eligible_ids = self.class.school_teachers_relation(school: school).pluck(:id).to_set

    teacher_ids.each do |teacher_id|
      teacher = GeneralUser.find_by(id: teacher_id)
      if teacher.blank?
        errors << { teacher_id: teacher_id, error: 'teacher_not_found' }
        next
      end

      if teacher.id == @actor.id
        errors << { teacher_id: teacher_id, error: 'cannot_share_with_self' }
        next
      end

      # Do not silently revoke historical shares while an owner edits other recipients.
      # A revoked share is not retained and must pass current eligibility again.
      next if retained_ids.include?(teacher.id)

      if teacher.locked_at.present?
        errors << { teacher_id: teacher_id, error: 'teacher_locked' }
        next
      end

      unless self.class.same_school_teacher?(school: school, teacher: teacher)
        errors << { teacher_id: teacher_id, error: 'not_same_school_teacher' }
        next
      end

      unless eligible_ids.include?(teacher.id)
        errors << { teacher_id: teacher_id, error: 'not_current_school_teacher' }
        next
      end

      eligible, ineligible_reason = eligibility_for_teacher(teacher, assignment_category)
      unless eligible
        errors << { teacher_id: teacher_id, error: ineligible_reason }
      end
    end

    errors
  end

  def eligibility_for_teacher(teacher, assignment_category)
    return [false, INELIGIBLE_MISSING_CATEGORY] if assignment_category.present? &&
                                                   !teacher.aienglish_features_list.include?(assignment_category) &&
                                                   assignment_category != 'sentence_puzzle'

    [true, nil]
  end

  def create_share!(teacher_id:, school:)
    @assignment.essay_assignment_shares.create!(
      owner_general_user_id: @assignment.general_user_id,
      shared_with_general_user_id: teacher_id,
      shared_by_general_user_id: @actor.id,
      school_id: school.id,
      school_academic_year_id: optional_academic_year_id(school),
      status: :active
    )
  end

  def optional_academic_year_id(school)
    if @actor&.aienglish_global_admin?
      return @assignment.school_academic_year_id if @assignment&.school_academic_year_id.present?

      return @assignment&.assignment_distributions
                        &.where.not(school_academic_year_id: nil)
                        &.order(created_at: :desc)
                        &.pick(:school_academic_year_id)
    end

    @actor.current_teaching_assignment&.school_academic_year_id || school.current_academic_year&.id
  end

  def active_shared_teacher_payloads
    @assignment.active_essay_assignment_shares
             .includes(:shared_with_general_user)
             .map(&:teacher_json)
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      next_page: collection.next_page,
      prev_page: collection.prev_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count
    }
  end
end
