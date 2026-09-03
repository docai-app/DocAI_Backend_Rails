# frozen_string_literal: true

# Compact assignment-list payload. Metrics are shared with the grading detail API.
class EssayGradingSubmissionPayloadBuilder
  def self.call(essay_grading, assignment_category:)
    return nil unless essay_grading.essay_assignment_id.present?

    grading = essay_grading.grading.is_a?(Hash) ? essay_grading.grading.deep_stringify_keys : {}
    comprehension = grading['comprehension'].is_a?(Hash) ? grading['comprehension'] : {}
    listening = grading['listening'].is_a?(Hash) ? grading['listening'] : {}
    user = essay_grading.general_user
    {
      id: essay_grading.id,
      general_user: {
        id: essay_grading.general_user_id, nickname: user&.nickname,
        class_name: user&.banbie, class_no: user&.class_no
      },
      using_time: essay_grading.using_time,
      newsfeed_id: essay_grading.newsfeed_id,
      category: assignment_category,
      created_at: essay_grading.created_at, updated_at: essay_grading.updated_at,
      status: essay_grading.status,
      questions_count: comprehension['questions_count'] || listening['questions_count'],
      play_count: listening['play_count'].to_i,
      submission_class_name: essay_grading.submission_class_name,
      submission_class_number: essay_grading.submission_class_number
    }.merge(EssayGradingMetrics.call(essay_grading, category: assignment_category))
  end
end
