# frozen_string_literal: true

# Builds the same essay_grading payload shape as Api::Admin::V1::EssayGradingsController#show.
module SchoolPortalEssayGradingJson
  extend ActiveSupport::Concern

  private

  def essay_grading_show_payload(essay_grading)
    grading_json = begin
      JSON.parse(essay_grading.grading['data']['text'])
    rescue StandardError
      {}
    end

    scores = grading_json.each_with_object({}) do |(key, value), result|
      next unless key.start_with?('Criterion') && value.is_a?(Hash)

      value.each do |criterion_key, criterion_value|
        result[criterion_key] = criterion_value unless ['Full Score', 'explanation'].include?(criterion_key)
      end
    end

          if essay_grading.category.to_s == 'comprehension'
      score = essay_grading.grading.dig('comprehension', 'score')
      full_score = essay_grading.grading.dig('comprehension', 'full_score')
          elsif essay_grading.category.to_s == 'speaking_pronunciation'
      score = essay_grading['score']
      full_score = 100
    else
      score = essay_grading.grading['score']
      full_score = essay_grading.grading['full_score']
    end

    {
      id: essay_grading.id,
      topic: essay_grading.topic,
      created_at: essay_grading.created_at,
      updated_at: essay_grading.updated_at,
      status: essay_grading.status,
      number_of_suggestion: essay_grading.grading['number_of_suggestion'],
      questions_count: essay_grading.grading.dig('comprehension', 'questions_count'),
      full_score: full_score,
      score: score,
      scores: scores,
      grading: essay_grading.grading,
      general_context: essay_grading.general_context,
      essay: essay_grading.essay,
      meta: essay_grading.meta,
      using_time: essay_grading.using_time,
      file: essay_grading.file.attached? ? essay_grading.file.url : nil,
      submission_class_name: essay_grading.submission_class_name,
      submission_class_number: essay_grading.submission_class_number,
      general_user: {
        id: essay_grading.general_user.id,
        nickname: essay_grading.general_user.nickname,
        class_name: essay_grading.general_user.banbie,
        class_no: essay_grading.general_user.class_no
      },
      essay_assignment: {
        id: essay_grading.essay_assignment.id,
        title: essay_grading.essay_assignment.title,
        category: essay_grading.essay_assignment.category,
        remark: essay_grading.essay_assignment.remark,
        answer_visible: essay_grading.essay_assignment.answer_visible,
        newsfeed_id: essay_grading.essay_assignment.newsfeed_id,
        meta: essay_grading.essay_assignment.meta,
        rubric: essay_grading.essay_assignment.rubric,
        created_at: essay_grading.essay_assignment.created_at,
        updated_at: essay_grading.essay_assignment.updated_at
      }
    }
  end
end
