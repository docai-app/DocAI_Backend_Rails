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
    validation_errors = validate_recipient_ids(normalized_ids, school)
    raise ShareError.new('Invalid share recipients', details: validation_errors) if validation_errors.any?

    active_shares = @assignment.essay_assignment_shares.active.index_by(&:shared_with_general_user_id)
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

    teachers = self.class.school_teachers_relation(
      school: school,
      exclude_user_id: @actor&.id
    ).to_a

    teacher_rows = teachers.map do |teacher|
      profile = teacher_profile_for_school(teacher, school)

      {
        id: teacher.id,
        email: teacher.email,
        nickname: teacher.nickname,
        department: profile[:department],
        position: profile[:position]
      }
    end

    {
      teachers: teacher_rows,
      departments: self.class.departments_for_school(school)
    }
  end

  def self.school_teachers_relation(school:, exclude_user_id: nil)
    teacher_ids = school_teacher_ids(school: school)
    teacher_ids -= [exclude_user_id] if exclude_user_id.present?

    GeneralUser
      .where(id: teacher_ids)
      .order(Arel.sql('LOWER(COALESCE(general_users.nickname, general_users.email)) ASC'))
  end

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
    school_id = school.id
    active_teacher_status = TeacherAssignment.statuses[:active]

    TeacherAssignment
      .joins(:school_academic_year, :general_user)
      .where(school_academic_years: { school_id: school_id })
      .where(status: active_teacher_status)
      .where("general_users.meta->>'aienglish_role' = ?", TEACHER_ROLE)
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
    return if @assignment.owned_by?(@actor)

    raise ShareError, 'Only the assignment owner can manage shares'
  end

  def actor_school!
    school = self.class.school_for_teacher(@actor)
    raise ShareError, 'School context is required' if school.blank?

    school
  end

  def normalize_teacher_ids(teacher_ids)
    Array(teacher_ids).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  def validate_recipient_ids(teacher_ids, school)
    errors = []
    assignment_category = @assignment.category

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

      unless self.class.same_school_teacher?(school: school, teacher: teacher)
        errors << { teacher_id: teacher_id, error: 'not_same_school_teacher' }
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

  def teacher_profile_for_school(teacher, school)
    assignment = teacher.teacher_assignments
                      .joins(:school_academic_year)
                      .where(school_academic_years: { school_id: school.id })
                      .where(status: TeacherAssignment.statuses[:active])
                      .order(updated_at: :desc)
                      .first

    {
      department: assignment&.department,
      position: assignment&.position
    }
  end
end
