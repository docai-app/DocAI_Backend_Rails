# frozen_string_literal: true

class ListeningAudioPlayback
  class InvalidRequest < StandardError; end
  class LimitReached < StandardError; end

  # Controller must authorize assignment access first. Counts are scoped to
  # assignment/user, never a disposable grading or client-supplied play_count.
  def self.call(assignment:, user:, request_id:, reader: ListeningAudioReader.new)
    unless request_id.is_a?(String) && request_id.match?(/\A[a-zA-Z0-9_-]{16,64}\z/)
      raise InvalidRequest, 'Provide a unique playback request ID'
    end
    snapshot = assignment.listening_assignment_snapshot if assignment.category == 'listening'
    raise InvalidRequest, 'Listening content is unavailable' unless snapshot
    limit = assignment.meta.dig('listening', 'play_limit')
    unless limit.nil? || (limit.is_a?(Integer) && limit.between?(1, 20))
      raise InvalidRequest, 'Listening playback configuration is invalid'
    end
    state = ListeningPlaybackState.create_or_find_by!(essay_assignment: assignment, general_user: user)
    state.with_lock do
      # Only the latest request can be retried, for a short transport recovery
      # window. Reusing an expired ID does not create another free issue.
      same_request = state.last_request_id == request_id
      retrying = same_request && state.last_issued_at && state.last_issued_at > 1.minute.ago
      raise InvalidRequest, 'Playback retry has expired; use a new request ID' if same_request && !retrying
      raise LimitReached, 'Listening play limit reached' if !retrying && limit && state.play_count >= limit
      bytes = reader.read(snapshot)
      unless retrying
        state.update!(play_count: state.play_count + 1, last_request_id: request_id, last_issued_at: Time.current)
      end
      { bytes: bytes, play_count: state.play_count, play_limit: limit }
    end
  end
end
