# frozen_string_literal: true

module AssignmentDraftGuard
  extend ActiveSupport::Concern

  included do
    before_validation :retain_assignment_draft_receipt
    around_save :guard_assignment_draft
    around_destroy :lock_assignment_draft_destroy
    after_destroy :restore_excluded_assignment_draft_counter
  end

  private

  def retain_assignment_draft_receipt
    return unless persisted?
    receipt = attribute_in_database('meta')&.dig(AssignmentDraftSession::KEY)
    self.meta = (meta || {}).reverse_merge(AssignmentDraftSession::KEY => receipt) if receipt
  end

  def guard_assignment_draft
    # Workers update submitted rows under a row lock; they must not acquire the
    # advisory lock in the reverse order from a student draft write.
    return yield unless draft? && essay_assignment_id && general_user_id
    AssignmentDraftSession.synchronize(essay_assignment_id, general_user_id) do
      if draft?
        stored_status = self.class.where(id: id).pick(:status) if persisted?
        duplicate = self.class.where(essay_assignment_id: essay_assignment_id,
          general_user_id: general_user_id, status: :draft).where.not(id: id).exists?
        if duplicate || (stored_status && stored_status != 'draft' && !@admin_draft_transition)
          errors.add(:base, 'Please reopen your saved work. Another draft or submitted record already exists.')
          raise ActiveRecord::RecordInvalid, self
        end
      end
      yield
    end
  end

  def lock_assignment_draft_destroy
    return yield unless essay_assignment_id && general_user_id
    AssignmentDraftSession.synchronize(essay_assignment_id, general_user_id) do
      stored_meta = self.class.where(id: id).pick(:meta) || {}
      @destroying_excluded_draft = stored_meta.dig(AssignmentDraftSession::KEY, 'counter_excluded') == true
      yield
    end
  end

  def restore_excluded_assignment_draft_counter
    EssayAssignment.increment_counter(:number_of_submission, essay_assignment_id) if @destroying_excluded_draft
  end
end
