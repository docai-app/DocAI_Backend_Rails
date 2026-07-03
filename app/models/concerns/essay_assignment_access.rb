# frozen_string_literal: true

module EssayAssignmentAccess
  extend ActiveSupport::Concern

  included do
    has_many :essay_assignment_shares, dependent: :destroy
    has_many :active_essay_assignment_shares,
             -> { active },
             class_name: 'EssayAssignmentShare',
             inverse_of: :essay_assignment
    has_many :shared_with_teachers,
             through: :active_essay_assignment_shares,
             source: :shared_with_general_user
  end

  def owned_by?(user)
    user.present? && general_user_id == user.id
  end

  def shared_with?(user)
    return false if user.blank?

    active_essay_assignment_shares.exists?(shared_with_general_user_id: user.id)
  end

  def accessible_by?(user)
    owned_by?(user) || shared_with?(user)
  end

  def access_type_for(user)
    return 'owner' if owned_by?(user)
    return 'shared' if shared_with?(user)

    nil
  end

  def can_share?(user)
    owned_by?(user)
  end

  def can_delete?(user)
    owned_by?(user)
  end

  def can_assign_to_students?(user)
    accessible_by?(user) && category_enabled_for?(user)
  end

  def can_duplicate?(user)
    accessible_by?(user) && category_enabled_for?(user)
  end

  def category_enabled_for?(user)
    return false if user.blank?
    
    user.aienglish_features_list.include?(category) || category == 'sentence_puzzle'
  end

  def shared_by_for(user)
    return nil unless shared_with?(user)

    general_user
  end

  def shared_by_label_for(user)
    sharer = shared_by_for(user)
    return nil if sharer.blank?

    display_name = sharer.nickname.presence || sharer.email
    "Shared by #{display_name}"
  end
end
