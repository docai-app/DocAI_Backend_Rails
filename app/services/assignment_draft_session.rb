# frozen_string_literal: true

require 'digest'

# Coordinates all student assignment writes, without changing their scoring logic.
# Locks are per student/assignment, not per school or whole assignment class.
class AssignmentDraftSession
  class Conflict < StandardError; end
  KEY = 'assignment_draft_session'
  attr_reader :written_now, :submitted_now, :created_now

  def self.synchronize(assignment_id, user_id)
    EssayGrading.transaction do
      key = Digest::SHA256.digest("assignment-draft:#{assignment_id}:#{user_id}").unpack1('q>')
      EssayGrading.connection.execute("SELECT pg_advisory_xact_lock(#{key})")
      yield
    end
  end

  def initialize(assignment:, user:)
    @assignment, @user = assignment, user
  end

  def current
    rows = scope.where(status: :draft).order(:created_at).limit(2).to_a
    raise Conflict, 'Your saved drafts need review. Please contact your teacher.' if rows.size > 1
    rows.first
  end

  def prepare(request_id)
    validate_key!(request_id)
    self.class.synchronize(@assignment.id, @user.id) do
      existing = scope.where("jsonb_exists(meta -> ? -> 'open_requests', ?)", KEY, request_id).first
      next existing if existing
      row = current || scope.new(status: :draft, topic: @assignment.topic)
      state = (row.meta[KEY] || {}).deep_dup
      state['counter_excluded'] = true if row.persisted? && row.is_sentence_puzzle? && !row.meta.key?(KEY)
      keys = Array(state['open_requests'])
      raise Conflict, 'Please close other assignment tabs and contact your teacher.' if keys.size >= 200
      state['open_requests'] = keys | [request_id]
      state['revision'] ||= 0
      state['versioned'] = true
      new_row = row.new_record?
      state['counter_excluded'] = true if new_row
      row.meta = row.meta.merge(KEY => state)
      yield row if block_given?
      row.save!
      EssayAssignment.decrement_counter(:number_of_submission, @assignment.id) if new_row
      row
    end
  end

  # The caller applies category-specific validation, scoring and attachments
  # inside this transaction. A replay never calls that block a second time.
  def write(attributes, row: nil, request_id: nil, revision: nil, operation: 'save', after_save: nil)
    @written_now = @submitted_now = @created_now = false
    validate_key!(request_id) if request_id.present?
    digest = Digest::SHA256.hexdigest(JSON.generate(canonical([operation, attributes])))
    self.class.synchronize(@assignment.id, @user.id) do
      draft = current
      record = row ? scope.lock.find(row.id) : nil
      if record.nil? && request_id.present?
        record = scope.where("meta -> ? -> 'last_write' ->> 'id' = ?", KEY, request_id).first
        if record.nil? && @assignment.category == 'listening'
          legacy = scope.where("meta -> 'listening_create_request' ->> 'key' = ?", request_id).first
          if legacy
            unless legacy.meta.dig('listening_create_request', 'digest') == ListeningSubmissionFingerprint.call(attributes)
              raise Conflict, 'This request was already used for different answers.'
            end
            next legacy
          end
        end
      end
      record ||= draft || scope.new(status: :draft, topic: @assignment.topic)
      state = (record.meta[KEY] || {}).deep_dup
      # Legacy puzzle drafts were excluded from the counter by their controller.
      if record.persisted? && record.is_sentence_puzzle? && !record.meta.key?(KEY)
        state['counter_excluded'] = true
      end
      previous = state['last_write'] || {}
      if request_id.present? && previous['id'] == request_id
        raise Conflict, 'This request was already used for different answers.' unless previous['digest'] == digest
        next record
      end
      raise Conflict, 'This work has already been submitted. Please view your submission.' if record.persisted? && !record.draft?
      raise Conflict, 'Please open your saved draft before submitting.' if draft && record.id != draft.id
      if (state['versioned'] || Array(state['open_requests']).any?) && (revision.nil? || request_id.blank?)
        raise Conflict, 'Please reopen your saved draft before saving or submitting.'
      end
      if !revision.nil? && revision.to_s != (state['revision'] || 0).to_s
        raise Conflict, 'Your saved work changed in another tab. Please reopen it to check.'
      end
      if record.new_record?
        @created_now = true
        state['counter_excluded'] = true
        record.meta = record.meta.merge(KEY => state)
        record.save!
        EssayAssignment.decrement_counter(:number_of_submission, @assignment.id)
      end
      yield record
      state['revision'] = (state['revision'] || 0) + 1
      state['versioned'] = true if request_id.present? && !revision.nil?
      state['last_write'] = { 'id' => request_id, 'digest' => digest }
      count_submission = !record.draft? && state['counter_excluded'] == true
      state['counter_excluded'] = false if count_submission
      record.meta = record.meta.merge(KEY => state)
      record.save!
      after_save.call(record) if after_save
      EssayAssignment.increment_counter(:number_of_submission, @assignment.id) if count_submission
      @written_now = true
      @submitted_now = !record.draft?
      record
    end
  end

  private

  def scope
    @assignment.essay_gradings.where(general_user: @user)
  end

  def validate_key!(key)
    raise Conflict, 'Please reload the assignment and try again.' unless key.to_s.match?(/\A[a-zA-Z0-9_-]{16,64}\z/)
  end

  def canonical(value)
    case value
    when ActionDispatch::Http::UploadedFile
      position = value.tempfile.pos
      value.tempfile.rewind
      digest = Digest::SHA256.file(value.tempfile.path).hexdigest
      value.tempfile.seek(position)
      { 'file_sha256' => digest, 'content_type' => value.content_type, 'filename' => value.original_filename }
    when ActionController::Parameters then canonical(value.to_h)
    when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
