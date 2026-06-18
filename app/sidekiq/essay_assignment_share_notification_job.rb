# frozen_string_literal: true

# Reserved for future email / in-app notifications when an assignment is shared.
class EssayAssignmentShareNotificationJob
  include Sidekiq::Worker

  def perform(essay_assignment_share_id)
    share = EssayAssignmentShare.find_by(id: essay_assignment_share_id)
    return if share.blank?

    Rails.logger.info(
      "[EssayAssignmentShareNotificationJob] Notification stub for share #{essay_assignment_share_id}"
    )

    # TODO: deliver email / in-app notification
    # share.update!(notified_at: Time.current)
  end
end
