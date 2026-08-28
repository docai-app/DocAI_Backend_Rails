# frozen_string_literal: true

# 將單筆 EssayGrading 轉為與 Api::V1::EssayAssignmentsController#show 中 essay_gradings 條目一致的字典
#（依 assignment category 解析 grading JSON、計算 full_score / overall_score / scores 等）
class EssayGradingSubmissionPayloadBuilder
  def self.call(essay_grading, assignment_category:)
    new(essay_grading, assignment_category: assignment_category).build
  end

  def initialize(essay_grading, assignment_category:)
    @eg = essay_grading
    @assignment_category = assignment_category
    @is_sentence_builder = assignment_category == 'sentence_builder'
    @is_comprehension = assignment_category == 'comprehension'
    @is_speaking_pronunciation = assignment_category == 'speaking_pronunciation'
    @is_speaking_essay = assignment_category == 'speaking_essay'
    @is_listening = assignment_category == 'listening'
    @is_sentence_puzzle = assignment_category == 'sentence_puzzle'
  end

  # @return [Hash, nil] nil 僅在 essay_assignment_id 缺失時
  def build
    return nil unless @eg.essay_assignment_id.present?

    grading_data = @eg.grading || {}
    grading_data_hash = grading_data.is_a?(Hash) ? grading_data.deep_stringify_keys : {}
    grading_text = begin
      grading_data_hash.dig('data', 'text')
    rescue StandardError => e
      Rails.logger.warn "Error getting grading text for EssayGrading #{@eg.id}: #{e.message}"
      nil
    end

    grading_json = nil
    if !@is_sentence_builder && !@is_comprehension && !@is_speaking_pronunciation && !@is_listening && !@is_sentence_puzzle
      grading_json = effective_assignment_grading_json(@eg, grading_text)
    end

    scores = {}
    overall_score = nil
    the_full_score = nil
    number_of_suggestion = effective_number_of_suggestion(grading_text, grading_data_hash['number_of_suggestion'])
    comprehension_data = grading_data_hash['comprehension'] || {}
    listening_data = grading_data_hash['listening'] || {}
    listening_play_count = listening_data['play_count']
    listening_play_count = listening_play_count.to_i if listening_play_count.present?

    if @is_sentence_builder
      begin
        sentence_builder_data = grading_data_hash['sentence_builder']

        if sentence_builder_data.is_a?(Hash) && sentence_builder_data['score'].present?
          the_full_score = sentence_builder_data['full_score']
          overall_score = sentence_builder_data['score']
        elsif sentence_builder_data.is_a?(Array)
          sb_item = sentence_builder_data.find { |item| item.is_a?(Hash) && item['score'].present? }
          if sb_item
            the_full_score = sb_item['full_score']
            overall_score = sb_item['score']
          elsif grading_text.present?
            begin
              response = AiJsonParser.object(grading_text)
              raise JSON::ParserError, 'Missing sentence results' unless response['results'].is_a?(Array)
              total_score = response['results']&.size || 0
              score = 0
              response['results']&.each do |result|
                score += 1 if result['errors']&.all? { |error| error['error1'] == 'Correct' }
              end
              the_full_score = total_score
              overall_score = score
            rescue StandardError => e
              Rails.logger.error "Error parsing sentence builder data for EssayGrading #{@eg.id}: #{e.message}"
            end
          end
        elsif grading_text.present?
          begin
            response = AiJsonParser.object(grading_text)
            raise JSON::ParserError, 'Missing sentence results' unless response['results'].is_a?(Array)
            total_score = response['results']&.size || 0
            score = 0
            response['results']&.each do |result|
              score += 1 if result['errors']&.all? { |error| error['error1'] == 'Correct' }
            end
            the_full_score = total_score
            overall_score = score
          rescue StandardError => e
            Rails.logger.error "Error parsing sentence builder data for EssayGrading #{@eg.id}: #{e.message}"
          end
        end
      rescue StandardError => e
        Rails.logger.error "Error calculating sentence builder score for EssayGrading #{@eg.id}: #{e.message}"
      end
    elsif @is_comprehension
      the_full_score = comprehension_data['questions_count']
      overall_score = comprehension_data['score']
    elsif @is_speaking_pronunciation
      the_full_score = 100
      raw = @eg.read_attribute(:score)
      overall_score = raw.nil? || raw.to_s == 'null' ? nil : raw.to_i
    elsif @is_listening
      the_full_score = listening_data['full_score']
      overall_score = listening_data['score']
    elsif @is_sentence_puzzle
      sentence_puzzle_data = sentence_puzzle_score_data
      the_full_score = sentence_puzzle_data[:total]
      overall_score = sentence_puzzle_data[:score]
    elsif @is_speaking_essay
      overall_score = normalize_assignment_score(grading_json&.dig('Overall Score') || grading_json&.dig('overall_score'))
      the_full_score = normalize_assignment_score(grading_json&.dig('Full Score') || grading_json&.dig('full_score')) || 9
      speaking_report_scores = speaking_report_scores(@eg)
      if speaking_report_scores.present?
        overall_score = speaking_report_scores['overall_band_score'] ||
                  @eg.grading['overall_score'] ||
                    @eg['score']
          the_full_score = @eg.grading['full_score'] || 9
          scores = speaking_report_scores
      end
    elsif grading_json
      if grading_json['criteria'].is_a?(Hash)
        scores = grading_json['criteria'].each_with_object({}) do |(criterion_name, criterion_value), result|
          next unless criterion_value.is_a?(Hash)

          result[criterion_name] = criterion_value['score'] || criterion_value[:score] || criterion_value['value'] || criterion_value[:value]
        end
        overall_score = normalize_assignment_score(grading_json['overall_score'] || grading_json['Overall Score'])
        the_full_score = normalize_assignment_score(grading_json['full_score'] || grading_json['Full Score'])
      else
        scores = grading_json.each_with_object({}) do |(key, value), result|
          next unless key.start_with?('Criterion') && value.is_a?(Hash)

          value.each do |criterion_key, criterion_value|
            result[criterion_key] = criterion_value unless ['Full Score', 'explanation'].include?(criterion_key)
          end
        end

        overall_score = normalize_assignment_score(grading_json['Overall Score'] || grading_json['overall_score'])
        the_full_score = normalize_assignment_score(grading_json['Full Score'] || grading_json['full_score'])
      end
    end

    general_user = @eg.general_user

    {
      id: @eg.id,
      general_user: {
        id: @eg.general_user_id,
        nickname: general_user&.nickname,
        class_name: general_user&.banbie,
        class_no: general_user&.class_no
      },
      using_time: @eg.using_time,
      newsfeed_id: @eg.newsfeed_id,
      category: @assignment_category,
      created_at: @eg.created_at,
      updated_at: @eg.updated_at,
      status: @eg.status,
      number_of_suggestion: number_of_suggestion,
      questions_count: comprehension_data['questions_count'] || listening_data['questions_count'],
      play_count: listening_play_count || 0,
      full_score: the_full_score,
      score: overall_score,
      scores: scores,
      overall_score: overall_score,
      the_full_score: the_full_score,
      submission_class_name: @eg.submission_class_name,
      submission_class_number: @eg.submission_class_number
    }
  end

  private

  # Historical counters may be zero because the old parser rejected a wrapper.
  # Recompute from the stored feedback at read time; do not rerun AI or write data.
  def effective_number_of_suggestion(grading_text, stored_count)
    return stored_count unless %w[essay speaking_conversation speaking_essay sentence_builder].include?(@assignment_category)

    sentences = @eg.teacher_review_hash.dig('grammar', 'sentences') if @eg.respond_to?(:teacher_review_hash)
    if sentences.is_a?(Array)
      return sentences.sum do |sentence|
        errors = sentence.is_a?(Hash) ? sentence['errors'] : nil
        errors.is_a?(Hash) || errors.is_a?(Array) ? errors.size : 0
      end
    end
    return stored_count if grading_text.blank?

    parsed = source_grading_json(grading_text)
    if @is_sentence_builder
      return nil unless parsed['results'].is_a?(Array)

      parsed['results'].sum do |result|
        errors = result.is_a?(Hash) ? result['errors'] : nil
        errors.is_a?(Array) ? errors.count { |error| error.is_a?(Hash) && error['error1'] != 'Correct' } : 0
      end
    else
      @eg.count_errors(parsed)
    end
  rescue JSON::ParserError
    nil
  end

  def source_grading_json(grading_text)
    @source_grading_json ||= AiJsonParser.object(grading_text)
  end

  def effective_assignment_grading_json(essay_grading, fallback_grading_text = nil)
    teacher_review_score = if essay_grading.respond_to?(:teacher_review_hash)
                             essay_grading.teacher_review_hash.dig('score', 'data')
                           elsif essay_grading.respond_to?(:meta) && essay_grading.meta.is_a?(Hash)
                             essay_grading.meta.dig('teacher_review', 'score', 'data')
                           end
    return teacher_review_score if teacher_review_score.is_a?(Hash) && teacher_review_score.present?

    grading_text = fallback_grading_text
    if grading_text.blank? && essay_grading.respond_to?(:grading)
      grading_hash = essay_grading.grading.is_a?(Hash) ? essay_grading.grading.deep_stringify_keys : {}
      grading_text = grading_hash.dig('data', 'text')
    end

    source_grading_json(grading_text)
  rescue StandardError => e
    Rails.logger.warn "Error parsing effective grading JSON for EssayGrading #{essay_grading.try(:id)}: #{e.message}"
    {}
  end

  def speaking_report_scores(essay_grading)
    scores = essay_grading.grading.dig('speaking_report', 'scores') ||
             essay_grading.grading['speaking_scores'] ||
             essay_grading.grading['scores']

    scores.is_a?(Hash) ? scores.deep_stringify_keys : {}
  end

  def sentence_puzzle_score_data
    attempt =
      if @eg.respond_to?(:meta) && @eg.meta.is_a?(Hash)
        @eg.meta['sentence_puzzle_attempt']
      end

    if attempt.is_a?(Hash)
      return {
        score: attempt['score'],
        total: attempt['total']
      }
    end

    puzzle_data = @eg.grading.is_a?(Hash) ? @eg.grading['sentence_puzzle'] : nil
    if puzzle_data.is_a?(Hash)
      return {
        score: puzzle_data['score'],
        total: puzzle_data['total']
      }
    end

    { score: @eg.score, total: nil }
  end

  def normalize_assignment_score(raw_score)
    return nil unless raw_score.is_a?(Numeric) || raw_score.is_a?(String)

    value = Float(raw_score, exception: false)
    return nil unless value&.finite?

    value == value.to_i ? value.to_i : value
  end
end
