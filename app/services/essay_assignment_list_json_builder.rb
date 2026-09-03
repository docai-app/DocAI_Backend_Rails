# frozen_string_literal: true

class EssayAssignmentListJsonBuilder
  def self.build(assignment, user:, list_access_type: nil)
    new(assignment, user, list_access_type).build
  end

  def initialize(assignment, user, list_access_type = nil)
    @assignment = assignment
    @user = user
    @list_access_type = list_access_type
  end

  def build
    access_type = @list_access_type.presence || @assignment.access_type_for(@user)
    json = @assignment.as_list_json

    json.merge!(
      'access_type' => access_type,
      'shared_with_me' => access_type == 'shared',
      'can_edit' => assignment_manageable?,
      'can_delete' => @assignment.can_delete?(@user),
      'can_share' => @assignment.can_share?(@user),
      'can_assign_to_students' => @assignment.can_assign_to_students?(@user),
      'can_duplicate' => @assignment.can_duplicate?(@user),
      'owner' => owner_payload
    )

    if access_type == 'shared'
      json['shared_by'] = owner_payload
      json['shared_by_label'] = @assignment.shared_by_label_for(@user)
    end

    if access_type == 'owner'
      json['shared_teachers'] = shared_teachers_payload
    end

    json
  end

  private

  def assignment_manageable?
    @user&.aienglish_global_admin? ||
      @assignment.owned_by?(@user) ||
      (@assignment.shared_with?(@user) && @assignment.category_enabled_for?(@user))
  end

  def owner_payload
    owner = @assignment.general_user
    return nil if owner.blank?

    {
      'id' => owner.id,
      'email' => owner.email,
      'nickname' => owner.nickname
    }
  end

  def shared_teachers_payload
    @assignment.active_essay_assignment_shares
             .includes(:shared_with_general_user)
             .map(&:teacher_json)
             .map { |teacher| teacher.transform_keys(&:to_s) }
  end
end
