# frozen_string_literal: true

module ListeningAssignmentVersionGuard
  extend ActiveSupport::Concern

  included do
    validate :preserve_listening_assignment_version, on: :update
  end

  private

  def preserve_listening_assignment_version
    return unless will_save_change_to_category? || will_save_change_to_meta?
    return unless ListeningAssignmentSnapshot.exists?(essay_assignment_id: id)

    # Playback settings are part of the assignment contract too. Recreate the
    # assignment to change them; labels/title can still be edited independently.
    errors.add(:base, 'Listening content and settings are fixed; create a new assignment to change them')
  end
end
