# frozen_string_literal: true

module SpeakingConversationPresetQuestions
  extend ActiveSupport::Concern

  private

  def load_preset_speaking_conversation_grading
    @essay_grading = current_general_user.essay_gradings.find(params[:id])

    unless preset_speaking_conversation_assignment?(@essay_grading.essay_assignment)
      render json: { success: false, error: 'This assignment does not use preset speaking conversation questions.' },
             status: :unprocessable_entity
      return false
    end

    true
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Essay grading not found.' }, status: :not_found
    false
  end

  def preset_speaking_conversation_assignment?(assignment)
    assignment&.category == 'speaking_conversation' &&
      assignment.meta.is_a?(Hash) &&
      assignment.meta.dig('speaking_conversation', 'mode') == 'preset_questions'
  end

  def preset_speaking_conversation_questions(assignment)
    questions = assignment.meta.dig('speaking_conversation', 'questions')
    return [] unless questions.is_a?(Array)

    questions
      .each_with_index
      .map do |question, index|
        next unless question.is_a?(Hash)

        normalized = question.deep_stringify_keys
        normalized['id'] = preset_question_id(normalized, fallback_index: index)
        normalized['order'] = normalized['order'].presence || index + 1
        normalized['text'] = normalized['text'].to_s.strip
        normalized
      end
      .compact
      .select { |question| question['text'].present? }
      .sort_by { |question| question['order'].to_i }
  end

  def preset_question_id(question, fallback_index: nil)
    question['id'].presence || "q_#{(fallback_index || 0) + 1}"
  end

  def preset_speaking_conversation_answers(essay_grading)
    Array(essay_grading.grading.dig('speaking_conversation', 'answers')).map do |answer|
      answer.is_a?(Hash) ? answer.deep_stringify_keys : answer
    end
  end

  def preset_speaking_conversation_draft_request?(assignment, grading_params)
    preset_speaking_conversation_assignment?(assignment) &&
      grading_params[:status].to_s == 'draft'
  end

  def apply_preset_speaking_conversation_defaults!(essay_grading, assignment)
    essay_grading.status = :draft
    essay_grading.grading ||= {}
    essay_grading.grading['speaking_conversation'] ||= {
      'mode' => 'preset_questions',
      'answers' => []
    }
    essay_grading.grading['speaking_conversation']['mode'] ||= 'preset_questions'
    essay_grading.grading['speaking_conversation']['answers'] ||= []

    return unless assignment.rubric.present? && assignment.rubric['app_key'].present?

    essay_grading.grading['app_key'] = assignment.rubric['app_key']['grading']
    essay_grading.general_context = { 'app_key' => assignment.rubric['app_key']['general_context'] }
    essay_grading.revised_essay = { 'app_key' => assignment.revised_essay_workflow_app_key }
  end

  def serialize_preset_speaking_conversation_grading(essay_grading)
    {
      id: essay_grading.id,
      uuid: essay_grading.id,
      status: essay_grading.status,
      answers: preset_speaking_conversation_answers(essay_grading)
    }
  end

  def speaking_conversation_answer_params
    raw_answer =
      if params[:answer].present?
        params.require(:answer).permit(
          :question_id,
          :question_order,
          :question_text,
          :answer_text,
          :answer_audio_base64,
          :answer_audio_url,
          :answered_at
        )
      else
        params.permit(
          :question_id,
          :question_order,
          :question_text,
          :answer_text,
          :answer_audio_base64,
          :answer_audio_url,
          :answered_at
        )
      end

    raw_answer.to_h
  end

  def normalize_speaking_conversation_answer(raw_answer, question_id:)
    answer = raw_answer.deep_stringify_keys
    answer['question_id'] = question_id
    answer['question_order'] = answer['question_order'].to_i if answer['question_order'].present?
    answer['answered_at'] = answer['answered_at'].presence || Time.current.iso8601(3)
    answer
  end

  def build_preset_speaking_conversation_essay(assignment_questions, saved_answers)
    assignment_questions.map do |question|
      question_id = preset_question_id(question)
      answer = saved_answers.find { |item| item['question_id'].to_s == question_id }
      question_text = answer&.dig('question_text').presence || question['text']
      answer_text = answer&.dig('answer_text').to_s.strip

      "Q: #{question_text}\nA: #{answer_text}"
    end.join("\n\n")
  end
end
