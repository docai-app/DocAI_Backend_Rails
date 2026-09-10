# frozen_string_literal: true

class ListeningAssignmentCreator
  class Error < StandardError; end

  # Authorization and owner assignment must precede this call in the controller.
  def self.call(assignment:, client: ListeningQgVersionClient.new)
    raise Error, 'A new listening assignment is required' unless assignment.new_record? && assignment.category == 'listening'

    selection = assignment.meta.is_a?(Hash) && assignment.meta['listening']
    raise Error, 'Select a published listening version' unless selection.is_a?(Hash)

    attributes = client.fetch(version_id: selection['version_id'], news_feed_id: selection['news_feed_id'], level: selection['level'])
    # No client question, transcript, answer key or audio URL survives in meta.
    settings = selection.slice('play_limit', 'allow_pause', 'allow_seek')
    limit = settings['play_limit']
    unless limit.nil? || (limit.is_a?(Integer) && limit.between?(1, 20))
      raise Error, 'Listening play limit must be between 1 and 20'
    end
    %w[allow_pause allow_seek].each do |key|
      raise Error, 'Invalid listening playback setting' if settings.key?(key) && ![true, false].include?(settings[key])
    end
    assignment.meta = { 'listening' => settings.merge(
      'version_id' => attributes.fetch(:qg_version_id), 'news_feed_id' => selection['news_feed_id'].to_s,
      'level' => attributes.fetch(:level), 'questions_count' => attributes.fetch(:quiz).fetch('full_score')
    ) }
    assignment.class.transaction do
      assignment.save!
      ListeningAssignmentSnapshot.create!(attributes.merge(essay_assignment: assignment))
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    # Snapshot validation errors must also be visible on the assignment response.
    assignment.errors.add(:base, 'Listening snapshot could not be saved') unless error.record == assignment
    false
  end
end
