# frozen_string_literal: true

module AssignmentDraftEndpoints
  extend ActiveSupport::Concern

  included do
    include ActiveStorage::SetCurrent
  end

  private

  def assignment_draft_session(record = nil)
    AssignmentDraftSession.new(assignment: record&.essay_assignment || @essay_assignment,
                              user: record&.general_user || current_general_user)
  end

  def draft_response(record)
    return nil unless record
    visible_grading = record.listening_grading_for_display
    if record.is_listening? && record.draft?
      listening = record.grading['listening'] || {}
      visible_grading = { 'listening' => listening.slice('play_count', 'play_limit', 'remaining_plays').merge(
        'questions' => Array(listening['questions']).map { |question| question.slice('id', 'user_answer') }) }
    end
    {
      id: record.id, status: record.status, essay_assignment_id: record.essay_assignment_id,
      topic: record.topic, essay: record.essay, grading: visible_grading,
      meta: record.meta, using_time: record.using_time,
      file: record.file.attached? ? record.file.url : nil
    }
  end

  def prepare_assignment_draft
    assert_embed_assignment!(@essay_assignment) if embed_session?
    return if performed?
    return unless ensure_assignment_package_item_access(@essay_assignment)
    session = assignment_draft_session
    record = if request.post?
               session.prepare(params[:request_id]) do |draft|
                 apply_assignment_workflow_app_keys!(draft, @essay_assignment)
                 if preset_speaking_conversation_assignment?(@essay_assignment)
                   apply_preset_speaking_conversation_defaults!(draft, @essay_assignment)
                 end
               end
             else
               session.current
             end
    link_assignment_package_grading_if_needed(record) if record
    response.headers['Cache-Control'] = 'no-store'
    render json: { success: true, essay_grading: draft_response(record) }
  rescue AssignmentDraftSession::Conflict => e
    render json: { success: false, error: e.message }, status: :conflict
  rescue ActiveRecord::RecordInvalid
    render json: { success: false, error: 'Your saved work could not be opened. Please contact your teacher.' }, status: :unprocessable_entity
  end

  def write_assignment_draft(grading_params, record: nil)
    @essay_assignment ||= record.essay_assignment
    attrs = essay_grading_attributes_for_persistence(@essay_assignment.category, grading_params).deep_stringify_keys
    status = attrs.fetch('status', record&.status || 'pending').to_s
    status = EssayGrading.statuses.key(status.to_i) if status.match?(/\A\d+\z/)
    unless %w[draft pending graded].include?(status)
      raise AssignmentDraftSession::Conflict, 'Please save a draft or submit your work.'
    end
    # Student submission is never permission to mark a Dify workflow completed.
    attrs['status'] = status == 'draft' ? 'draft' : 'pending'
    if @essay_assignment.category == 'comprehension' && status != 'draft'
      questions = attrs.dig('grading', 'comprehension', 'questions')
      unless questions.is_a?(Array) && questions.any?
        raise AssignmentDraftSession::Conflict, 'Please wait for the questions to load before submitting.'
      end
    end
    session = assignment_draft_session(record)
    callback = lambda do |saved|
      run_speaking_essay_workflow_after_attachment(saved, force: saved.status != 'draft')
    end
    @essay_grading = session.write(grading_params.to_h, row: record,
      request_id: params[:request_id].presence || request.headers['Idempotency-Key'].presence,
      revision: params[:draft_revision], after_save: callback) do |draft|
      draft.assign_attributes(attrs.except('meta'))
      draft.meta = draft.meta.merge(attrs.fetch('meta', {}))
      if @essay_assignment.category == 'listening' && request.headers['Idempotency-Key'].present?
        draft.meta['listening_create_request'] = { 'key' => request.headers['Idempotency-Key'],
          'digest' => ListeningSubmissionFingerprint.call(grading_params.to_h) }
      end
      if preset_speaking_conversation_draft_request?(@essay_assignment, grading_params)
        apply_preset_speaking_conversation_defaults!(draft, @essay_assignment)
      elsif sentence_puzzle_submission_request?(@essay_assignment, grading_params)
        apply_sentence_puzzle_submission!(draft, grading_params)
      else
        apply_assignment_workflow_app_keys!(draft, @essay_assignment)
      end
      persist_uploaded_attachment!(essay_grading: draft, category: @essay_assignment.category,
        uploaded_file: grading_params[:file], prepared_attachment: nil)
    end
    if session.written_now
      link_assignment_package_grading_if_needed(@essay_grading)
      if session.submitted_now
        update_assignment_status_if_needed
        update_assignment_package_progress_if_needed(@essay_grading)
      end
    end
    render json: { success: true, data: @essay_grading.id, essay_grading: draft_response(@essay_grading) },
      status: session.created_now ? :created : :ok
  rescue AssignmentDraftSession::Conflict => e
    render json: { success: false, error: e.message }, status: :conflict
  rescue ActiveRecord::RecordInvalid
    render json: { success: false, error: 'Your work could not be saved. Please check your answers and try again.' }, status: :unprocessable_entity
  end
end
